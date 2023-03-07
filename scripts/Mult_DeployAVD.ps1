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
# $buildPath = Join-Path -Path $repoPath -ChildPath 'build'
$ParametersPath = Join-Path -Path $repoPath -ChildPath 'params'

Write-Host "##[debug]🐞`tINFO - Get Multi Session config details for Business Unit Id $($p_businessUnitId) HostPool Id $($p_hostPoolId)"

$PSDefaultParameterValues = @{
    '*:EnvShortName'   = $p_env
    '*:BusinessUnitId' = $p_businessUnitId
    '*:HostPoolId'     = $p_hostPoolId
    '*:RepositoryPath' = $repoPath
    '*:ParametersPath' = $ParametersPath
}
Write-Host "Default Param Values - $($PSDefaultParameterValues)"
Invoke-Expression $(Join-Path -Path $scriptsPath -ChildPath 'Mult_InitializePreReqs.ps1')

# Get deployment variables
try {
    $envNames = Get-MultiEnvNames
    $deployVars = Get-MultiDeploymentVars
} catch {
    throw 'Failed to get deployment variables, check parameter files!'
}


Write-Host "$($FunctionName): INFO - Config details obtained for Hostpool : $($envNames.hostPoolName)"
Write-Host ""; Write-Host ""
Write-Host "$($envNames)"
Write-Host ""; Write-Host ""
Write-Host "$($FunctionName): INFO - Get deployment variables for Hostpool $($envNames.hostPoolName)"


$p_tags = @{
    buildAutomationLink = 'None' # "$($env:SYSTEM_COLLECTIONURI)$($env:SYSTEM_TEAMPROJECT)/_build/results?buildId=$($env:BUILD_BUILDID)&view=results"
    releaseDate         = Get-Date -UFormat '%Y-%m-%d'
    gitCommitId         = 'None' # "$($env:BUILD_SOURCEVERSION)"
}

# Collect required role assignment group id's, role id's and target resource
$avdVirtualMachineUserLoginGroupId = (Get-MSGraphAADGroup -GroupName $envNames.avdVirtualMachineUserLoginGroup).id
$p_groupId = $avdVirtualMachineUserLoginGroupId
Write-Host "$($FunctionName): INFO - Group ID for $($envNames.appGroupName) = $avdVirtualMachineUserLoginGroupId"

Write-Host "##[group]$($functionName): INFO - Preparing AVD objects for deployment"

#Set BICEP template location.
$Biceptemp = Join-Path -Path $bicepPath -ChildPath 'avd' -AdditionalChildPath 'main.bicep'

#Obtain AVD Broker subscription and resource group details
$AVDBrokerSubscription = $deployVars.environment.avdBrokerSubscriptionName
$AVDResourceGroup = $deployVars.environment.avdResourceGroup

$rdpPropertiesConfigPath = Join-Path -Path $ParametersPath -ChildPath 'RDPProperties.json'
Write-Host "$($FunctionName): INFO - Import RDP properties type $(($deployVars.hostPoolConfig.hostpool.rdpProperties)) from $($rdpPropertiesConfigPath)"
$rdpJSON = Get-Content $rdpPropertiesConfigPath -raw | ConvertFrom-Json | ForEach-Object $($deployVars.hostPoolConfig.hostpool.rdpProperties)

# Join RDP properties as a string with ; separator
$customRdpProperty = ($rdpJSON.psobject.properties | ForEach-Object { $_.name + ":" + $_.value }) -join ";"

# Set AzContext to AVD Broker subscription
if ((Get-AzContext).Subscription.Name -eq $AVDBrokerSubscription) {
    Write-Host "$($FunctionName): INFO - Current Context : $((Get-AzContext).Subscription.Name)"
}else{
    Write-Host "$($FunctionName): INFO - Current Context : $((Get-AzContext).Subscription.Name)"
    Write-Host "$($FunctionName): INFO - Setting Context to $($AVDBrokerSubscription) "
    # Output to unused variable to avoid noise in function output...
    $SetAzCon = Set-AzContext -Subscription $AVDBrokerSubscription
    Write-Host "$($FunctionName): INFO - Context set : $((Get-AzContext).Subscription.Name)"
}

# Check to see if workspace already exists
Write-Host "$($FunctionName): INFO - Checking to see if Workspace : $($envNames.WorkspaceName) exists"
$Workspacecheck = Get-AzWvdWorkspace -ResourceGroupName $AVDResourceGroup -Name $envNames.WorkspaceName -ErrorAction SilentlyContinue
if (!$Workspacecheck) {
    Write-Host "$($FunctionName): INFO - Workspace : $($envNames.WorkspaceName) doesn't exist and will be deployed"
    $p_ExistsWorkspace = $false
}else{
    Write-Host "$($FunctionName): INFO - Workspace : $($envNames.WorkspaceName) already exist"
    $p_ExistsWorkspace = $true
}

# Set deployment name to have hostPoolName, date, number of VMs
$deploymentName = "deploy_AVD_$($envNames.hostPoolName)_$(Get-Date -f yyMMddHHmmss)"

Write-Host ""; Write-Host ""
Write-Host "**********************************************************************************************************"
Write-Host "$($functionName): INFO - Getting ready for deployment - $deploymentName"
Write-Host "**********************************************************************************************************"
Write-Host "$($FunctionName): INFO - AVD Resource Group : $($AVDResourceGroup)"
Write-Host "$($FunctionName): INFO - Environment : $p_env"
Write-Host "$($functionName): INFO - Biceptemp : $Biceptemp"
Write-Host "$($functionName): INFO - Business Unit ID : $p_businessUnitId"
Write-Host "$($functionName): INFO - Hostpool ID : $p_hostPoolId"
Write-Host "$($functionName): INFO - Hostpool : $($envNames.hostPoolName)"
Write-Host "$($functionName): INFO - Workspace : $($envNames.WorkspaceName)"
Write-Host "$($functionName): INFO - Existing Workspace : $($p_ExistsWorkspace)"
Write-Host "$($functionName): INFO - RDPProperties Type : $($deployVars.hostPoolConfig.hostpool.rdpProperties)"
Write-Host "$($functionName): INFO - Default App Group : $($envNames.appGroupName)"
Write-Host "$($functionName): INFO - RDP properties : $($customRdpProperty.split(";"))"

try {
    Write-Host ""; Write-Host ""
    Write-Host "**********************************************************************************************************"
    Write-Host "($functionName): INFO - Starting deployment - $deploymentName"
    Write-Host "**********************************************************************************************************"
    Start-Transcript "$($deploymentName)_Transcript.txt" | Out-Null
    Write-Host "$($functionName): INFO - Running AVD component deployment using $Biceptemp for Business Unit ID $($p_businessUnitId), Hostpool ID $($p_hostPoolId) "
    Write-Host "$($functionName): INFO - Please wait..."

    $deployParams = @{
        ErrorAction          = 'Stop'
        Name                 = $deploymentName
        ResourceGroupName    = $AVDResourceGroup
        TemplateFile         = $Biceptemp
        p_envNames           = $envNames | ConvertTo-Json | ConvertFrom-Json -AsHashtable
        p_globalVars         = $deployVars.global
        p_hostPoolConfig     = $deployVars.hostPoolConfig
        p_ExistsWorkspace    = $p_ExistsWorkspace
        p_customRdpProperty  = $customRdpProperty
        p_groupId            = $p_groupId
        p_tags               = $p_tags
        Verbose              = $true
    }
    # Output to unused variable to avoid noise in function output...
    $deployment = New-AzResourceGroupDeployment @deployParams

    Write-Host "$($functionName): INFO - Complete!"
    $EXITCODE = 0

} catch {
    Write-Host "##[error]$($functionName): ERROR - An operation for deployment $deploymentName has reported an error"
    Write-Host "##[error]$($functionName): ERROR - Showing transcript for ARM failure below..."

    Stop-Transcript | Out-Null
    Get-Content "$($deploymentName)_Transcript.txt" | ForEach-Object { write-host "##[error]$($functionName): ERROR - $_" }
    $EXITCODE = 1
}
Write-Host "**********************************************************************************************************"
Write-Host "$($functionName): INFO - Completed deployment of AVD resources for - $deploymentName"
Write-Host "**********************************************************************************************************"

# Deploy friendly name for application group session desktop application
Write-Host "$($functionName): INFO - Update sessiondesktop application friendly name to $($envNames.appGroupFriendlyName))"

try {

    $FriendlyNameObj = Update-AzWvdDesktop -ResourceGroupName $AVDResourceGroup -ApplicationGroupName $envNames.appGroupName `
    -FriendlyName $envNames.appGroupFriendlyName -Name SessionDesktop -verbose

} catch {
    write-host "$($functionName): ERROR - There was an error updating sessiondesktop application friendly name to $($envNames.appGroupFriendlyName) for application group $($envNames.appGroupFriendlyName)) application group. Cannot continue with deployment."
    write-host "$_"
    $EXITCODE = 1
    RETURN $EXITCODE
}

if ($group -eq $true) { Write-Host "##[endgroup]" }
Write-Host "$($functionName): INFO - Exiting with ExitCode of $exitCode."
Write-Host "**********************************************************************************************************"
Write-Host "$($FunctionName): INFO - ******************** Leave function $FunctionName ********************"
Write-Host "**********************************************************************************************************"
RETURN $EXITCODE