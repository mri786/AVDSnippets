#Requires -PSEdition Core
#Requires -Version 7.0

param (
    [Parameter(Mandatory = $true, HelpMessage = 'Business Unit Id')]
    [ValidatePattern('^\d{3}$')]
    [string]$p_businessUnitId,
    [Parameter(Mandatory = $true, HelpMessage = 'Hostpool Id')]
    [ValidatePattern('^\d{2}$')]
    [string]$p_hostPoolId,
    [Parameter(Mandatory = $true, HelpMessage = 'Azure environment')]
    [ValidateSet('int', 'ppd', 'prd')]
    [string]$p_env
)

$ErrorActionPreference = 'Stop'
if ((Get-ChildItem -Path $env:BUILD_SOURCESDIRECTORY).Name -contains $env:BUILD_REPOSITORY_NAME) {
    $repoPath = Join-Path -Path $env:BUILD_SOURCESDIRECTORY -ChildPath $env:BUILD_REPOSITORY_NAME
} else {
    $repoPath = $env:BUILD_SOURCESDIRECTORY
}

$scriptsPath = Join-Path -Path $repoPath -ChildPath 'scripts'
$bicepPath = Join-Path -Path $repoPath -ChildPath 'bicep'
$buildPath = Join-Path -Path $repoPath -ChildPath 'build'
$ParametersPath = Join-Path -Path $repoPath -ChildPath 'params'

$PSDefaultParameterValues = @{
    '*:EnvShortName'   = $p_env
    '*:BusinessUnitId' = $p_businessUnitId
    '*:HostPoolId'     = $p_hostPoolId
    '*:RepositoryPath' = $repoPath
    '*:ParametersPath' = $ParametersPath
}

Invoke-Expression $(Join-Path -Path $scriptsPath -ChildPath 'Mult_InitializePreReqs.ps1')

try {
    $envNames = Get-MultiEnvNames
    $deployVars = Get-MultiDeploymentVars
} catch {
    throw 'Failed to get deployment variables, check parameter files!'
}

$labContext = Set-AzContext -SubscriptionId $envNames.labSubId

# Update storage account auth methods for NTFS script
try {
    Write-Host "##[debug]🐞`tConfiguring temporary storage account settings for deployment..."
    $acc = Get-azStorageAccount -ResourceGroupName $envNames.saResourceGroupName -Name $envNames.fslogixStorageAccount
    Update-AzStorageFileServiceProperty -StorageAccount $acc -SMBAuthenticationMethod Kerberos, NTLMv2
    Set-AzStorageAccount -ResourceGroupName $envNames.saResourceGroupName -Name $envNames.fslogixStorageAccount -AllowSharedKeyAccess $true
} catch {
    Write-Host "##[error]❗`tERROR: $_"
    throw 'Error preparing storage account, aborting!'
}

# try {
#     Write-Host "##[debug]🐞`t Toggling AADKERB..."
#     Set-AzStorageAccount -ResourceGroupName $envNames.saResourceGroupName -StorageAccountName $envNames.fslogixStorageAccount -EnableAzureActiveDirectoryKerberosForFile $false
#     Write-Host "##[debug]🐞`t Sleeping for 60 seconds"
#     Start-Sleep -Seconds 60
#     Set-AzStorageAccount -ResourceGroupName $envNames.saResourceGroupName -StorageAccountName $envNames.fslogixStorageAccount -EnableAzureActiveDirectoryKerberosForFile $true -ActiveDirectoryDomainName $deployVars.environment.haadjDomainToJoin -ActiveDirectoryDomainGuid 'f70769ba-cdf7-4a8e-ae90-d34f58bb4287'
# } catch {
#     throw 'Error toggling AADKERB, aborting!'
# }

# Add pipeline tags
$p_tags = @{
    buildAutomationLink = "$($env:SYSTEM_COLLECTIONURI)$($env:SYSTEM_TEAMPROJECT)/_build/results?buildId=$($env:BUILD_BUILDID)&view=results"
    releaseDate         = Get-Date -UFormat '%Y-%m-%d'
    gitCommitId         = "$($env:BUILD_SOURCEVERSION)"
}

# WSS install command
$p_WSScmd = 'cmd /c msiexec /i ' + $($deployVars.environment.WSSAgentFileLocation) + ' /passive MCU=1'

# Constuct runCommand to save redirections.xml to tempVM ready for uploading
$redirectionXMLFileName = 'redirections.xml' # FSLogix expects a file called redirections.xml
$redirXMLPath = Join-Path -Path $buildPath -ChildPath 'fslogix' -AdditionalChildPath $redirectionXMLFileName
$redirXML = Get-Content -Path $redirXMLPath -Raw
$redirTempFilePath = '$env:temp\{0}' -f $redirectionXMLFileName
$pwshCmd = 'Set-Content -Path {0} -Value ''{1}'' -Force; Get-Content -Path {0} -Raw' -f $redirTempFilePath, $redirXML
$encodedpwshCmd = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($pwshCmd))
$setRedirCmd = "powershell.exe -NoProfile -EncodedCommand $encodedpwshCmd -force"

# Ensure managed identity exists
$msi_tags = @{
    securityClassification = $deployVars.hostPoolConfig.sessionHosts.securityClassification
    costCentre             = $deployVars.global.tags.costCentre
    resourceOwner          = $deployVars.global.tags.resourceOwner
    CMDB_AppID             = $deployVars.global.tags.CMDB_AppID
}
$msiDeploymentParams = @{
    ErrorAction       = 'Stop'
    AzContext         = $labContext
    Name              = "fslogix-msi-$(Get-Date -UFormat %s)"
    ResourceGroupName = $envNames.saResourceGroupName
    TemplateFile      = $(Join-Path -Path $bicepPath -ChildPath 'fslogix' -AdditionalChildPath 'fslogix_identity.bicep')
    p_TempVmName      = $deployVars.global.fslogix.tempVMName
    p_location        = 'uksouth'
    p_tags            = $p_tags + $msi_tags
    Verbose           = $true
}
Write-Host "##[debug]🐞`tFSlogix msi deployment parameters:"
$msiDeploymentParams | ConvertTo-Json -Depth 100

try {
    Write-Host "##[debug]🐞`Running first New-AzDeployment for FSLogix msi"
    New-AzResourceGroupDeployment @msiDeploymentParams
} catch {
    Write-Host "##[error]❗`tFSLOGIX MSI ARM DEPLOYMENT FAILED"
    Write-Host "##[error]❗`tERROR: $_"
    throw 'Error pre-staging msi account, aborting!'
}

# Construct runCommand to set ntfs permissions on Azure Files shares
$assignedIdentityName = '{0}-fslogix-msi' -f $deployVars.global.fslogix.tempVMName
$ntfsScriptPath = Join-Path -Path $buildPath -ChildPath 'fslogix' -AdditionalChildPath 'Set-FSLogixFileShares.ps1'
$substitutions = @{
    userPermissionGroup       = $envNames.fslogixUserGroup
    storageAccountName        = $envNames.fslogixStorageAccount
    storageAccountRG          = $envNames.saResourceGroupName
    profileShareName          = $envNames.fslogixProfileShare
    redirectionShareName      = $deployVars.global.fslogix.redirectionShareName
    redirectionSourceFilePath = $redirTempFilePath
    azAccountClientid         = (Get-AzUserAssignedIdentity -ResourceGroupName $envNames.saResourceGroupName -Name $assignedIdentityName).ClientId
}
Write-Host "##[debug]🐞`tBuilding script file with substitutions:"
Build-DeploymentFile -Substitutions $substitutions -FilePath $ntfsScriptPath
$encodedNtfsScriptContent = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($(Get-Content -Path $ntfsScriptPath -Raw)))
$setNtfsCmd = "powershell.exe -NoProfile -EncodedCommand $encodedNtfsScriptContent"

$deployParams = @{
    ErrorAction          = 'Stop'
    AzContext            = $labContext
    Name                 = "fslogix-$($p_businessUnitId)-$($p_hostPoolId)-$(Get-Date -UFormat %s)"
    Location             = 'uksouth'
    TemplateFile         = $(Join-Path -Path $bicepPath -ChildPath 'fslogix' -AdditionalChildPath 'main.bicep')
    p_envNames           = $envNames | ConvertTo-Json | ConvertFrom-Json -AsHashtable
    p_globalVars         = $deployVars.global
    p_envVars            = $deployVars.environment
    p_hostPoolConfig     = $deployVars.hostPoolConfig
    p_localAdminPassword = $(New-Password)
    p_tags               = $p_tags
    p_WSScmd             = $p_WSScmd
    Verbose              = $true
}

Write-Host "##[debug]🐞`tDeployment parameters:"
$deployParams | ConvertTo-Json -Depth 100

try {
    Write-Host "##[debug]🐞`Running main New-AzDeployment"
    New-AzDeployment @deployParams

    $p_tags.Add('securityClassification', 'Confidential')
    $p_tags.Add('costCentre', $deployVars.global.tags.costCentre)
    $p_tags.Add('resourceOwner', $deployVars.global.tags.resourceOwner)
    $p_tags.Add('CMDB_AppID', $deployVars.global.tags.CMDB_AppID)
    $vmRunParams = @{
        ResourceGroupName = $envNames.vmResourceGroupName
        VMName            = $deployVars.global.fslogix.tempVMName
        Location          = $deployVars.hostPoolConfig.location
        Tag               = $p_tags
        TimeoutInSecond   = 600
    }

    Write-Host "##[debug]🐞`Running setRedirectionXml runCommand"
    $setRedirFileParams = @{
        RunCommandName = 'setRedirectionXml'
        SourceScript   = $setRedirCmd
    }
    $cmdResult = Set-AzVMRunCommand @vmRunParams @setRedirFileParams

    Write-Host "##[debug]🐞`setRedirectionXml runCommand output:"
    $resultParams = @{
        ResourceGroupName = $vmRunParams.ResourceGroupName
        VMName            = $vmRunParams.VMName
        RunCommandName    = $setRedirFileParams.RunCommandName
        Expand            = 'InstanceView'
    }
    (Get-AzVMRunCommand @resultParams).InstanceView.Output

    Write-Host "##[debug]🐞`Running setNTFSPermissions runCommand"
    $setNTFSPermissions = @{
        RunCommandName = 'setNTFSPermissions'
        SourceScript   = $setNtfsCmd
    }
    $cmdResult = Set-AzVMRunCommand @vmRunParams @setNTFSPermissions

    Write-Host "##[debug]🐞`setNTFSPermissions runCommand output:"
    $resultParams = @{
        ResourceGroupName = $vmRunParams.ResourceGroupName
        VMName            = $vmRunParams.VMName
        RunCommandName    = $setNTFSPermissions.RunCommandName
        Expand            = 'InstanceView'
    }
    (Get-AzVMRunCommand @resultParams).InstanceView.Output
} catch {
    Write-Host "##[error]❗`tARM DEPLOYMENT FAILED"
    Write-Host "##[error]❗`tERROR: $_"
}

# Set FSLogix user group roles

try {
    $aadObject = Get-AzADGroup -displayName $envNames.fslogixUserGroup

    $azureRoleName = 'Storage File Data SMB Share Contributor'
    $roleDetails = Get-AzRoleDefinition -Name $azureRoleName -AzContext $labContext

    $storageAccount = Get-AzStorageAccount -ResourceGroupName $envNames.saResourceGroupName -Name $envNames.fslogixStorageAccount
    $ShareScope = $storageAccount.Id + '/fileServices/default/fileshares/' + $envNames.fslogixProfileShare
    $redirShareScope = $storageAccount.Id + '/fileServices/default/fileshares/' + $deployVars.global.fslogix.redirectionShareName
    try {
        Write-Host "##[debug]🐞`tAdding $($roleDetails.Name) role to AD Group $($aadObject.DisplayName) for $($envNames.fslogixProfileShare) share"
        $roleParams = @{
            ObjectId         = $aadObject.id
            RoleDefinitionId = $roleDetails.Id
            Scope            = $ShareScope
        }
        if (![bool](Get-AzRoleAssignment @roleParams -AzContext $labContext)) {
            New-AzRoleAssignment @roleParams
        }
    } catch {
        Write-Host "##[error]❗`tERROR: $_"
    }

    try {
        Write-Host "##[debug]🐞`tAdding $($roleDetails.Name) role to AD Group $($aadObject.DisplayName) for $($deployVars.global.fslogix.redirectionShareName) share"
        $roleParams = @{
            ObjectId         = $aadObject.id
            RoleDefinitionId = $roleDetails.Id
            Scope            = $redirShareScope
        }
        if (![bool](Get-AzRoleAssignment @roleParams -AzContext $labContext)) {
            New-AzRoleAssignment @roleParams
        }
    } catch {
        Write-Host "##[error]❗`tERROR: $_"
    }
} catch {
    Write-Host "##[error]❗`tERROR: $_"
}

try {
    Write-Host "##[debug]🐞`tSecuring storage account..."
    Update-AzStorageFileServiceProperty -StorageAccount $acc -SMBAuthenticationMethod Kerberos
    Set-AzStorageAccount -ResourceGroupName $envNames.saResourceGroupName -Name $envNames.fslogixStorageAccount -AllowSharedKeyAccess $false
} catch {
    Write-Host "##[error]❗`tERROR: $_"
}

try {
    Write-Host "##[debug]🐞`tRemoving temporary VM [$($deployVars.global.fslogix.tempVMName)]"
    Remove-AzVM -Name $deployVars.global.fslogix.tempVMName -ResourceGroupName $envNames.vmResourceGroupName -ForceDeletion $true -Force
} catch {
    Write-Host "##[error]❗`tERROR: $_"
}
