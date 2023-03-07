param (
    [Parameter(Mandatory = $false, HelpMessage = 'Parameter files path')]
    [string]$RepositoryPath = $env:BUILD_SOURCESDIRECTORY
)
$ErrorActionPreference = 'Stop'

Write-Host "##[debug]❗`tInitializing multi-session deployment prerequisites"

Write-Host "##[debug]❗`tChecking required Az module versions"
$azmodules = @(
    @{Name = 'Az.Resources'; MinVersion = [version]'6.5.1' }
    @{Name = 'Az.DesktopVirtualization'; MinVersion = [version]'3.1.1' }
)
$azmodules.ForEach({
        $mod = Get-Module -Name $PSItem.Name -ListAvailable | Sort-Object -Property Version -Descending | Select-Object -First 1
        Write-Host "##[debug]❗`tCurrent installed version of $($PSItem.Name) is $($mod.Version)"
        if ([bool]$mod -and ($mod.Version -ge $PSItem.MinVersion)) {
            Write-Host "##[debug]❗`tFound module $($mod.Name) with version $($mod.Version) which is greater than or equal to $($PSItem.MinVersion)"
            Write-Host "##[debug]❗`tImporting $($mod.Name)"
            Import-Module $mod.Name -Force
        } else {
            Write-Host "##[debug]❗`tModule $($PSItem.Name) either too old or not found"
            Write-Host "##[debug]❗`tInstalling newer version of module $($PSItem.Name)"
            Install-Module -Name $PSItem.Name -MinimumVersion $PSItem.MinVersion -Force -AllowClobber -Confirm:$false
        }
    })

$modulePath = Join-Path -Path $RepositoryPath -ChildPath "modules"
Write-Host "##[debug]❗`tImporting vdi modules under $($modulePath)"
foreach($module in (Get-ChildItem -Path "$(Join-Path -Path $modulePath -ChildPath 'vdi_*.psm1')")) {
    try {
        Write-Host "- $($module.Name)"
        Import-Module $module.FullName -ErrorAction Stop
    }
    catch {
        throw 'Failed to import all modules'
    }
}