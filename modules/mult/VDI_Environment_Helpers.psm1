#Requires -Modules @{ModuleName="Az.Accounts"; ModuleVersion="2.11.0"}

function Get-PSFunctionName {
    [CmdletBinding()]
    [OutputType([string])]
    [array]$functionStack = (Get-PSCallStack | Where-Object {
        ($PSItem.FunctionName -ine '<ScriptBlock>') -and ($PSItem.FunctionName -ine 'Get-PSFunctionName') }).FunctionName
    $functionName = (($functionStack[$($functionStack.Count)..0] -Join "\") -Replace "\<.*?\>", "")

    return $functionName
}

function Get-MultiEnvNames {
    [CmdletBinding()]
    [OutputType([object])]
    param (
        [Parameter(Mandatory = $false, HelpMessage = 'Environment shortname')]
        [ValidateSet('uks')]
        [string]$LocationShortName = 'uks',
        [Parameter(Mandatory = $true, HelpMessage = 'Environment shortname')]
        [ValidateSet('idv', 'int', 'ppd', 'prd')]
        [string]$EnvShortName,
        [Parameter(Mandatory = $true, HelpMessage = 'Business Unit Id')]
        [ValidateSet('001', '002', '003', '004', '005', '006', '007', '099', '999')]
        [string]$BusinessUnitId,
        [Parameter(Mandatory = $true, HelpMessage = 'Host pool Id')]
        [ValidateSet('01', '02', '03')]
        [string]$HostPoolId,
        [Parameter(Mandatory = $false, HelpMessage = 'Parameter files path')]
        [string]$ParametersPath = $(Join-Path -Path $env:BUILD_SOURCESDIRECTORY -ChildPath 'params'-AdditionalChildPath 'mult')
    )

    $functionName = Get-PSFunctionName

    # Get relevant host pool details
    $hostPoolConfigFileName = '{0}-EEE-vdi-avd-hpl-mult-{1}-{2}.json' -f $LocationShortName, $BusinessUnitId, $HostPoolId
    $hostPoolConfigPath = Join-Path -Path $ParametersPath -ChildPath 'hostpools' -AdditionalChildPath $hostPoolConfigFileName
    $hostPoolConfig = Get-Content -Path $hostPoolConfigPath | ConvertFrom-Json -Depth 100
    $labId = $hostPoolConfig.labId
    $shortLabId = $labId.TrimStart('v')

    # Get subcription details for host pool
    try {
        $subName = '{0}-vdi-lab-core-mult-{1}' -f $EnvShortName, $labId
        $subId = (Get-AzSubscription -SubscriptionName $subName).SubscriptionId
        $subShortId = ($subId -split '-')[1]
    } catch {
        Write-Host "##[error]❗`t$($functionName): Failed to retrieve subscription details to generate environment names"
        Write-Host "##[error]❗`t$($functionName): ERROR: $_"
        throw 'Error retrieving subscription details'
    }

    # Set MSG & workspace env based on $EnvshortName
    switch ($EnvShortName) {
        { $PSItem -ieq 'int' } { $msgEnv = 'DT' ; $workSpaceNameEnv = 'RTL'}
        { $PSItem -ieq 'ppd' } { $msgEnv = 'PP' ; $workSpaceNameEnv = 'RTL'}
        { $PSItem -ieq 'prd' } { $msgEnv = 'PR' ; $workSpaceNameEnv = 'Live'}
        Default {}
    }


    # Construct environment names based on agreed naming standards
    $environmentNames = [PSCustomObject]@{
        hostPoolName                     = '{0}-{1}-vdi-avd-hpl-mult-{2}-{3}' -f $LocationShortName, $EnvShortName, $BusinessUnitId, $HostPoolId
        hostPoolDescription              = '{0}-{1}-vdi-avd-hpl-mult-{2}-{3}' -f $LocationShortName, $EnvShortName, $BusinessUnitId, $HostPoolId
        hostPoolFriendlyName             = '{0}-{1}-vdi-avd-hpl-mult-{2}-{3}' -f $LocationShortName, $EnvShortName, $BusinessUnitId, $HostPoolId
        avdVirtualMachineUserLoginGroup  = 'MSG_{0}_AAD_VDI_HPL_MULT_{1}_{2}' -f $msgEnv.ToUpper(), $BusinessUnitId, $HostPoolId
        avdVirtualMachineAdminLoginGroup = $null
        avdVirtualMachineUserLoginRole   = 'AVD Virtual Machine User Login {0}' -f $subName
        avdVirtualMachineAdminLoginRole  = 'AVD Virtual Machine Admin Login {0}' -f $subName
        vmResourceGroupName              = '{0}-{1}-vdi-lab-core-mult-{2}-{3}-{4}-hosts-rsg' -f $LocationShortName, $EnvShortName, $labId, $BusinessUnitId, $HostPoolId
        workspaceName                    = '{0}-{1}-vdi-avd-wsp-remoteapps-01' -f $LocationShortName, $EnvShortName
        workspaceFriendlyName            = '{0} Remote Apps' -f $workSpaceNameEnv
        appGroupName                     = '{0}-{1}-vdi-avd-apg-mult-{2}-{3}' -f $LocationShortName, $EnvShortName, $BusinessUnitId, $HostPoolId
        appGroupDescription              = '{0}-{1}-vdi-avd-apg-mult-{2}-{3}' -f $LocationShortName, $EnvShortName, $BusinessUnitId, $HostPoolId
        appGroupFriendlyName             = 'Remote Apps {0}-{1}' -f $BusinessUnitId, $HostPoolId
        vnetName                         = '{0}-{1}-vdi-lab-core-mult-{2}-net-01' -f $LocationShortName, $EnvShortName, $labId
        vnetResourceGroupName            = '{0}-{1}-vdi-lab-core-mult-{2}-network-rsg' -f $LocationShortName, $EnvShortName, $labId
        subnetName                       = 'AVDSubnet-{0}' -f $BusinessUnitId
        asgName                          = '{0}-{1}-{2}-{3}-asg' -f $LocationShortName, $subName, $BusinessUnitId, $HostPoolId
        keyVaultName                     = '{0}-{1}-vdi-kvt-{2}-01' -f $LocationShortName, $EnvShortName, $subShortId
        keyVaultResourceGroupName        = '{0}-{1}-vdi-lab-core-mult-{2}-keyvault-rsg' -f $LocationShortName, $EnvShortName, $labId
        labSubName                       = $subName
        labSubId                         = $subId
        labdSubShortId                   = $subShortId
        locationShortName                = $LocationShortName
        dcrRuleName                      = 'uks-{0}-vdi-avd-dcr-mult' -f $EnvShortName
        saResourceGroupName              = '{0}-{1}-vdi-lab-core-mult-{2}-storage-rsg' -f $LocationShortName, $EnvShortName, $labId
        fslogixStorageAccount            = '{0}{1}vdimultilb{2}pf{3}' -f $LocationShortName, $EnvShortName, $shortLabId, $BusinessUnitId
        blobSaName                       = '{0}{1}vdimultilb{2}' -f $LocationShortName, $EnvShortName, $shortLabId
        fslogixProfileShare              = 'profiles-{0}-{1}' -f $BusinessUnitId, $HostPoolId
        fslogixUserGroup                 = 'UG_{0}_AAD_VDI_HPL_MULT_{1}_{2}' -f $msgEnv, $BusinessUnitId, $HostPoolId
        ntfsScript                       = '{0}-{1}-vdi-avd-hpl-mult-{2}-{3}.ps1' -f $LocationShortName, $EnvShortName, $BusinessUnitId, $HostPoolId
    }

    return $environmentNames
}

function Get-MultiDeploymentVars {
    [CmdletBinding()]
    [OutputType([object])]
    param (
        [Parameter(Mandatory = $false, HelpMessage = 'Environment shortname')]
        [ValidateSet('uks')]
        [string]$LocationShortName = 'uks',
        [Parameter(Mandatory = $true, HelpMessage = 'Environment shortname')]
        [ValidateSet('idv', 'int', 'ppd', 'prd')]
        [string]$EnvShortName,
        [Parameter(Mandatory = $true, HelpMessage = 'Business Unit Id')]
        [ValidateSet('001', '002', '003', '004', '005', '006', '007', '099', '999')]
        [string]$BusinessUnitId,
        [Parameter(Mandatory = $true, HelpMessage = 'Host pool Id')]
        [ValidateSet('01', '02', '03')]
        [string]$HostPoolId,
        [Parameter(Mandatory = $false, HelpMessage = 'Parameter files path')]
        [string]$ParametersPath = $(Join-Path -Path $env:BUILD_SOURCESDIRECTORY -ChildPath 'params'-AdditionalChildPath 'mult')
    )

    $functionName = Get-PSFunctionName

    try {
        $deployVars = [PSCustomObject]@{
            global         = Get-Content -Path $(Join-Path -Path $ParametersPath -ChildPath 'global.json') | ConvertFrom-Json -Depth 100 -AsHashtable
            environment    = Get-Content -Path $(Join-Path -Path $ParametersPath -ChildPath "$($EnvShortName)/environment.json") | ConvertFrom-Json -Depth 100 -AsHashtable
            hostPoolConfig = Get-Content -Path $(Join-Path -Path $ParametersPath -ChildPath "hostpools/$($LocationShortName)-EEE-vdi-avd-hpl-mult-$($BusinessUnitId)-$($HostPoolId).json") | ConvertFrom-Json -Depth 100 -AsHashtable
        }
    } catch {
        Write-Host "##[error]❗`t$($functionName): Failed to retrieve deployment variables from parameter files"
        Write-Host "##[error]❗`t$($functionName): ERROR: $_"
        throw 'Error retrieving deployment variables, aborting!'
    }

    return $deployVars
}

function Build-DeploymentFile {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true, HelpMessage = 'Variable substitution table')]
        [hashtable]$Substitutions,
        [Parameter(Mandatory = $true, HelpMessage = 'Source file to process for variable substitution')]
        [string]$FilePath
    )

    $functionName = Get-PSFunctionName

    try {
        $file = Get-Content -Path $FilePath -Raw
    } catch {
        Write-Host "##[error]❗`t$($functionName): Failed to retrieve deployment file for substitution"
        Write-Host "##[error]❗`t$($functionName): ERROR: $_"
        throw 'Failed to load file'
    }


    foreach ($sub in $Substitutions.keys) {
        $var = "#{variables.$($sub)}#"
        Write-Host "Replacing $($var) with $($Substitutions[$sub])"

        $file = $file -ireplace $var, $Substitutions[$sub]
    }

    $file | Set-Content -Path $FilePath

    if(Select-String -Path $FilePath -Pattern "#{variables..+}#" -Quiet) {
        Write-Host "`n##[error]❗`t$($functionName): The following patterns were missed:"
        Select-String -Path $FilePath -Pattern "#{variables..+}#"
        throw "Error: Some variable patterns were not replaced!"
    }

    $newFile = Get-Content $FilePath -Raw
    Write-Host "##[debug]🐞`t$($functionName): Returning new script file with substitutions:"
    return $newFile
}