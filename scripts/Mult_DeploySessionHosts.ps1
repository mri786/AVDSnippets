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
    [string]$p_env,
    [Parameter(Mandatory = $false, HelpMessage = 'Deploy next rotation of VMs')]
    [bool]$p_rotateVMs = $false,
    [Parameter(Mandatory = $false, HelpMessage = 'Register VMs with host pool')]
    [bool]$p_hostPoolRegistration = $false,
    [Parameter(Mandatory = $false, HelpMessage = 'Ignore untracked hosts')]
    [bool]$p_ignoreUntrackedHosts = $false
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
$parametersPath = Join-Path -Path $repoPath -ChildPath 'params'
$schemasPath = Join-Path -Path $repoPath -ChildPath 'schemas'

$PSDefaultParameterValues = @{
    '*:EnvShortName'   = $p_env
    '*:BusinessUnitId' = $p_businessUnitId
    '*:HostPoolId'     = $p_hostPoolId
    '*:RepositoryPath' = $repoPath
    '*:ParametersPath' = $parametersPath
}

Invoke-Expression $(Join-Path -Path $scriptsPath -ChildPath 'Mult_InitializePreReqs.ps1')

# Check for duplicate host names in config files, will abort if found
Write-Host "##[debug]🐞`tChecking all host pool host files for duplicates..."
Test-SessionHostNames

# Get deployment variables
try {
    $envNames = Get-MultiEnvNames
    $deployVars = Get-MultiDeploymentVars
} catch {
    throw 'Failed to get deployment variables, check parameter files!'
}

# Check host pool json configuration file against schema
$schemaFile = Join-Path -Path $schemasPath -ChildPath 'avd_hostpool.json'
Write-Host "##[debug]🐞`tValidating host pool config json [$($envNames.hostPoolConfigPath)] against schema: [$($schemaFile)]"

if (!([bool](Get-Content -Path $envNames.hostPoolConfigPath -Raw | Test-Json -SchemaFile $schemaFile))) {
    Write-Host "##[error]❗`tSchema validation failed with message: $((Get-Error).ErrorDetails.Message)"
    throw 'Host pool config file not valid against json schema'
} else {
    Write-Host "##[debug]🐞`tHost pool config json validated ok, continuing..."
}

$labContext = Set-AzContext -SubscriptionId $envNames.labSubId

$avdVirtualMachineUserLoginGroupId = (Get-MSGraphAADGroup -GroupName $envNames.avdVirtualMachineUserLoginGroup).id
$avdVirtualMachineUserLoginRoleId = (Get-AzRoleDefinition -Name $envNames.avdVirtualMachineUserLoginRole -Scope "/subscriptions/$($envNames.labSubId)").Id

# Collect required role assignment group id's, role id's and target resource
$resourceGroupRoleAssignments = @(
    @{
        groupId       = $avdVirtualMachineUserLoginGroupId
        roleId        = $avdVirtualMachineUserLoginRoleId
        resourceGroup = $envNames.vmResourceGroupName
    }
)

# Construct WSS agent install command
$WSSAgentFileLocation = $deployVars.environment.WSSAgentFileLocation
#$p_WSScmd = 'cmd /c certUtil -AddStore Root ' + $($WSSCloudCert) + ' && cmd /c msiexec /i ' + $($WSSAgentFileLocation) + ' /passive MCU=1 & IF %ERRORLEVEL% EQU 0 (echo 0) ELSE (IF %ERRORLEVEL% EQU 1602 (echo 1) ELSE (IF %ERRORLEVEL% EQU 3010 (echo 0)))'
$p_WSScmd = 'cmd /c msiexec /i ' + $($WSSAgentFileLocation) + ' /passive MCU=1'

# Check if host pool contains registered hosts that are not defined in the hosts config json, i.e shouldn't be there
if ((Get-UntrackedHosts -HostPoolName $envNames.hostPoolName) -and !$p_ignoreUntrackedHosts) {
    throw 'Detected untracked hosts registered to host pool, aborting as p_ignoreUntrackedHosts is false!'
}

# Generate required VM names based on base name and requested rotation
$vmRotationId = Get-VmRotationId -HostPoolName $envNames.hostPoolName -NextRotationId $p_rotateVMs
if ([bool]$vmRotationId) {
    $vmNames = Get-MultiVMNames -VMRotationId $vmRotationId
} else {
    throw 'No rotation id, aborting!'
}

# Allocate zones and detect existing VMs that are already registered with host pool
$currentRegisteredHosts = Get-HostPoolVMDetails -HostPoolName $envNames.hostPoolName
$hosts = Select-NewVmZones -VmNames $vmNames | Select-Object *, @{
    n = 'hostPoolRegistered'
    e = {
        switch ($PSItem.name) {
            { $PSItem -iin $currentRegisteredHosts.name } { $true }
            Default { $false }
        }
    }
}

# If $p_hostPoolRegistration is true then start any deallocated VMs that are not registered with the hostPool
# Do not start registered VMs as that will interfere with the scaling plan
if ($p_hostPoolRegistration) {
    $deallocatedVMs = $hosts.Where({
            ($PSItem.provisioningState -iin ('Succeeded', 'Updating')) -and
            ($PSItem.powerStateCode -iin ('PowerState/deallocated')) -and
            !$PSItem.hostPoolRegistered
        })
    if ([bool]$deallocatedVMs) {
        Write-Host "##[debug]🐞`tp_hostPoolRegistration is true, starting deallocated VMs in order to register with host pool"
        Write-Host "##[debug]🐞`tFound $($deallocatedVMs.Count) deallocated VMs, starting..."
        try {
            $deallocatedVMs | ForEach-Object -Parallel {
                Write-Host "##[debug]🐞`tStarting $($PSItem.name) with vmId $($PSItem.vmId) in $($PSItem.resourceGroup)"
                Start-AzVM -ResourceGroupName $PSItem.resourceGroup -Name $PSItem.name -Confirm:$false
            } -ThrottleLimit 10 -TimeoutSeconds 10800
        } catch {
            throw 'Error starting one or more existing VMs'
            ### FUTURE: capture failed and continue, skip bicep on failed ones ###
            # Ensure start-azvm doesn't abort on a failed vm
            # Get vms and see which ones haven't started
        }
    }
}

# Generate VM admin passwords, will only apply on VM creation
$localAdminPasswords = @{}
$hosts.ForEach({
        $ht = @{}
        $ht.Add($PSItem.name, $(New-Password))
        $localAdminPasswords += $ht
    })

# Get current host pool token and abort if no host pool token
try {
    $hpltokenParams = @{
        HostPoolName      = $envNames.hostPoolName
        ResourceGroupName = $deployVars.environment.avdResourceGroup
        SubscriptionId    = $deployVars.environment.avdBrokerSubscriptionId
    }
    $hplToken = (Get-AzWvdHostPoolRegistrationToken @hpltokenParams).Token | ConvertTo-SecureString -AsPlainText -Force
} catch {
    throw 'Error retrieving host pool token, aborting!'
}

$p_tags = @{
    buildAutomationLink = "$($env:SYSTEM_COLLECTIONURI)$($env:SYSTEM_TEAMPROJECT)/_build/results?buildId=$($env:BUILD_BUILDID)&view=results"
    releaseDate         = Get-Date -UFormat '%Y-%m-%d'
    gitCommitId         = "$($env:BUILD_SOURCEVERSION)"
    hostPool            = $envNames.hostPoolName
    vmRotationId        = $vmRotationId
}

$deployParams = @{
    ErrorAction            = 'Stop'
    AzContext              = $labContext
    Name                   = "hosts-$($p_businessUnitId)-$($p_hostPoolId)-$(Get-Date -UFormat %s)"
    Location               = 'uksouth'
    TemplateFile           = $(Join-Path -Path $bicepPath -ChildPath 'sessionhosts' -AdditionalChildPath 'main.bicep')
    p_envNames             = $envNames | ConvertTo-Json | ConvertFrom-Json -AsHashtable
    p_globalVars           = $deployVars.global
    p_envVars              = $deployVars.environment
    p_hostPoolConfig       = $deployVars.hostPoolConfig
    p_hosts                = $hosts | ConvertTo-Json | ConvertFrom-Json -AsHashtable
    p_hplToken             = $hplToken
    p_localAdminPasswords  = $localAdminPasswords
    p_hostPoolRegistration = $p_hostPoolRegistration
    p_tags                 = $p_tags
    p_WSScmd               = $p_WSScmd
    p_rgRoleAssignments    = $resourceGroupRoleAssignments | ConvertTo-Json | ConvertFrom-Json -AsHashtable
    Verbose                = $true
}
# Print deployParams to log
$deployParams | ConvertTo-Json -Depth 100

New-AzDeployment @deployParams
