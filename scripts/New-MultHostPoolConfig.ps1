
param (
    [Parameter(Mandatory = $true)]
    [string]$BusinessUnitId,
    [Parameter(Mandatory = $true)]
    [string]$BusinessUnitName,
    [Parameter(Mandatory = $false)]
    [string]$Location = 'uksouth',
    [Parameter(Mandatory = $true)]
    [string]$LabId,
    [Parameter(Mandatory = $true)]
    [string]$HostpoolId,
    [Parameter(Mandatory = $false)]
    [string]$HostpoolRdpProperties = 'MULT-copypaste',
    [Parameter(Mandatory = $false)]
    [int]$HostpoolMaxSessionLimit = 15,
    [Parameter(Mandatory = $false)]
    [string]$HostpoolPrefferedAppGroupType = 'Desktop',
    [Parameter(Mandatory = $false)]
    [string]$AgentUpdateType = 'Scheduled',
    [Parameter(Mandatory = $false)]
    [bool]$AgentUpdateUseSessionHostLocalTime = $false,
    [Parameter(Mandatory = $false)]
    [string]$AgentUpdateMaintenanceWindowTimeZone = 'GMT Standard Time',
    [Parameter(Mandatory = $false)]
    [int]$AgentUpdateMaintenanceWindowsHour = 1,
    [Parameter(Mandatory = $false)]
    [string]$AgentUpdateMaintenanceWindowsDayOfWeek = 'Saturday',
    [Parameter(Mandatory = $false)]
    [string]$AppGroupType = 'Desktop',
    [Parameter(Mandatory = $false)]
    [bool]$SessionHostHaadj = $true,
    [Parameter(Mandatory = $false)]
    [string]$SessionHostTimeZone = 'GMT Standard Time',
    [Parameter(Mandatory = $false)]
    [string]$SessionHostBuildImage = 'uks-img-windows-desktop-11-gen2-22h2ent-mult',
    [Parameter(Mandatory = $false)]
    [string]$SessionHostBuildImageVer = '2.3.1675942650',
    [Parameter(Mandatory = $false)]
    [string]$SessionHostSecurityClassification = 'Confidential',
    [Parameter(Mandatory = $false)]
    [string]$SessionHostVmSku = 'standard_D8s_v3',
    [Parameter(Mandatory = $false)]
    [string]$SessionHostVmDiskType = 'Premium_LRS',
    [Parameter(Mandatory = $false)]
    [int]$SessionHostVmDiskSizeGb = 128,
    [Parameter(Mandatory = $false)]
    [string]$SessionHostLocalAdminUsername = 'mshadmin'
)

class MultiSessionAgentMaintenanceWindow {
    [int] $hour
    [string] $dayOfWeek
}

class MultiSessionAgentUpdateSechedule {
    [string] $type
    [bool] $useSessionHostLocalTime
    [string] $maintenanceWindowTimeZone
    [MultiSessionAgentMaintenanceWindow] $maintenanceWindows
}

class MultiSessionHostPoolDetails {
    [string] $id
    [string] $rdpProperties
    [int] $maxSessionLimit
    [string] $prefferedappGroupType
    [MultiSessionAgentUpdateSechedule] $agentUpdate
}

class MultiSessionAppGroupDetails {
    [string] $type
}

class MultiSessionSessionHostDetails {
    [bool]   $haadj
    [string] $timeZone
    [string] $buildImage
    [string] $buildImageVer
    [string] $securityClassification
    [string] $vmSku
    [string] $vmDiskType
    [int]    $vmDiskSizeGb
    [string] $localAdminUsername
}

class MultiSessionHostPool {
    [string] $schema = '../../../schemas/avd_hostpool.json'
    [string] $businessUnitName
    [string] $location
    [string] $labId
    [MultiSessionHostPoolDetails] $hostpool
    [MultiSessionAppGroupDetails] $appGroup
    [MultiSessionSessionHostDetails] $sessionHosts
}

$agwindow = [MultiSessionAgentMaintenanceWindow]::new()
$agschedule = [MultiSessionAgentUpdateSechedule]::new()
$hpdetails = [MultiSessionHostPoolDetails]::new()
$agdetails = [MultiSessionAppGroupDetails]::new()
$hostdetails = [MultiSessionSessionHostDetails]::new()
$hpConfig = [MultiSessionHostPool]::new()
$hpConfig.businessUnitName = $BusinessUnitName
$hpConfig.location = $Location
$hpConfig.labId = $LabId
$agwindow.hour = $AgentUpdateMaintenanceWindowsHour
$agwindow.dayOfWeek = $AgentUpdateMaintenanceWindowsDayOfWeek
$agschedule.maintenanceWindows = $agwindow
$agschedule.type = $AgentUpdateType
$agschedule.useSessionHostLocalTime = $AgentUpdateUseSessionHostLocalTime
$agschedule.maintenanceWindowTimeZone = $AgentUpdateMaintenanceWindowTimeZone
$hpdetails.agentUpdate = $agschedule
$hpdetails.id = $HostpoolId
$hpdetails.rdpProperties = $HostpoolRdpProperties
$hpdetails.maxSessionLimit = $HostpoolMaxSessionLimit
$hpdetails.prefferedappGroupType = $HostpoolPrefferedAppGroupType
$hpConfig.hostpool = $hpdetails
$agdetails.type = $AppGroupType
$hpConfig.appGroup = $agdetails
$hostdetails.haadj = $SessionHostHaadj
$hostdetails.timeZone = $SessionHostTimeZone
$hostdetails.buildImage = $SessionHostBuildImage
$hostdetails.buildImageVer = $SessionHostBuildImageVer
$hostdetails.securityClassification = $SessionHostSecurityClassification
$hostdetails.vmSku = $SessionHostVmSku
$hostdetails.vmDiskType = $SessionHostVmDiskType
$hostdetails.vmDiskSizeGb = $SessionHostVmDiskSizeGb
$hostdetails.localAdminUsername = $SessionHostLocalAdminUsername
$hpConfig.sessionHosts = $hostdetails

$outfile = '..\params\mult\hostpools\uks-EEE-vdi-avd-hpl-mult-{0}-{1}.json' -f $BusinessUnitId, $HostpoolId
($hpConfig | ConvertTo-Json -Depth 100) -replace '"schema":','"$schema":' | Out-File $outfile -NoClobber

# e.g.
# .\New-MultHostPoolConfig.ps1 -BusinessUnitId 002 -HostpoolId 01 -LabId v01a -BusinessUnitName 'ReleaseOneDev'