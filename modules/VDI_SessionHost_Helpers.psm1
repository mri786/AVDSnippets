#Requires -PSEdition Core
#Requires -Version 7.0

function Get-HostPoolVMDetails {
    <#
    .SYNOPSIS
        Retreives properties of Azure virtual machines currently registered to the named host pool.
    .EXAMPLE
        Get-HostPoolVMDetails -HostPoolName 'uks-int-vdi-avd-hpl-mult-099-02'
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param (
        [Parameter(Mandatory = $true, HelpMessage = 'Name of the host pool to query')]
        [string]$HostPoolName
    )

    $functionName = Get-PSFunctionName

    # Get VMs currently registered hosts in given host pool
    $query = "desktopvirtualizationresources
        | where type =~ 'microsoft.desktopvirtualization/hostpools/sessionhosts' and id contains '/hostpools/$($HostPoolName)/'
        | project vmResourceId = tolower(tostring(properties.resourceId)), hplHostRef = tolower(name)
        | join kind=leftouter (
            resources
                | where type =~ 'microsoft.compute/virtualmachines' and isnotempty(zones)
                | extend Zone = substring(tostring(array_slice(zones,0,0)),2,1)
                | project vmResourceId = tolower(id), name, vmId = tolower(properties.vmId), Zone, resourceGroup,
                powerStateCode = (properties.extended.instanceView.powerState.code),
                provisioningState = (properties.provisioningState),
                vmRotationId=toupper(tags.vmRotationId),
                tags)
        on vmResourceId"
    try {
        $vmZones = Search-AzGraphRestAPI -Query $query
    } catch {
        Write-Host "##[error]❗`t$($functionName): Failed to retrieve current VM details"
        Write-Host "##[error]❗`t$($functionName): ERROR: $_"
        throw 'Error from Search-AzGraphRestAPI'
    }

    $zoneResults = $vmZones | Select-Object name, vmId, Zone, powerStateCode, provisioningState, vmRotationId, resourceGroup, tags, vmResourceId, hplHostRef

    return $zoneResults
}

function Get-SessionHostStatus {
    [CmdletBinding()]
    [OutputType([object])]
    param (
        [Parameter(Mandatory = $true, HelpMessage = 'Name of the host pool to query')]
        [string]$HostPoolName
    )

    $functionName = Get-PSFunctionName

    $query = "desktopvirtualizationresources | where type =~ 'microsoft.desktopvirtualization/hostpools/sessionhosts' and id contains '/hostpools/$($HostPoolName)/'
        | project name = split(properties.resourceId, '/')[-1], status = properties, vmResourceId = properties.resourceId"

    try {
        $sessionHostStatus = Search-AzGraphRestAPI -Query $query
    } catch {
        Write-Host "##[error]❗`t$($functionName): Failed to retrieve current VM details"
        Write-Host "##[error]❗`t$($functionName): ERROR: $_"
        throw 'Error from Search-AzGraphRestAPI'
    }

    return $sessionHostStatus
}

function Get-ProvisionedVMDetails {
    [CmdletBinding()]
    [OutputType([object])]
    param (
        [Parameter(Mandatory = $true, HelpMessage = 'Array of VM names to query')]
        [array]$VMNames
    )

    $functionName = Get-PSFunctionName

    # Get provisioned VMs from list regardless of host pool registration
    $query = "resources
        | where type =~ 'microsoft.compute/virtualmachines' and isnotempty(zones) and name in ($(($VMNames | ConvertTo-Json -Compress).Trim('[',']')))
        | extend Zone = substring(tostring(array_slice(zones,0,0)),2,1)
        | project vmResourceId = tolower(id), name, vmId = tolower(properties.vmId), Zone, resourceGroup,
        powerStateCode = (properties.extended.instanceView.powerState.code),
        provisioningState = (properties.provisioningState),
        vmRotationId=toupper(tags.vmRotationId),
        tags"

    try {
        $vmZones = Search-AzGraphRestAPI -Query $query
    } catch {
        Write-Host "##[error]❗`t$($functionName): Failed to retrieve current VM details"
        Write-Host "##[error]❗`t$($functionName): ERROR: $_"
        throw 'Error from Search-AzGraphRestAPI'
    }

    $zoneResults = $vmZones | Select-Object name, vmId, Zone, powerStateCode, provisioningState, vmRotationId, resourceGroup, tags, vmResourceId

    return $zoneResults
}

function Get-UntrackedHosts {
    [CmdletBinding()]
    [OutputType([object])]
    param (
        [Parameter(Mandatory = $true, HelpMessage = 'Name of the host pool to query')]
        [string]$HostPoolName,
        [ValidateSet('001', '002', '003', '004', '005', '006', '007', '099', '999')]
        [string]$BusinessUnitId,
        [Parameter(Mandatory = $true, HelpMessage = 'Host pool Id')]
        [ValidateSet('01', '02', '03')]
        [string]$HostPoolId,
        [Parameter(Mandatory = $false, HelpMessage = 'Parameter files path')]
        [string]$ParametersPath = $(Join-Path -Path $env:BUILD_SOURCESDIRECTORY -ChildPath 'params')
    )

    $functionName = Get-PSFunctionName

    $baseHostnames = Get-MultiBaseHostNames -BusinessUnitId $BusinessUnitId -HostPoolId $HostPoolId -ParametersPath $ParametersPath
    $currentRegisteredHosts = Get-HostPoolVMDetails -HostPoolName $HostPoolName | Select-Object *, @{n = 'baseName'; e = { $PSItem.name -replace ".$" } }
    $untrackedHosts = $currentRegisteredHosts.where({ $baseHostnames -inotcontains $PSItem.baseName })

    if ([bool]$untrackedHosts) {
        Write-Host "##[warning]❓`t$($functionName): Found untracked hosts registered to host pool"
        Write-Host "##[debug]🐞`t$($functionName): Untracked hosts:"
        $untrackedHosts.ForEach({
                Write-Host "Host Pool Host Reference: $($PSitem.hplHostRef), VM Name: $($PSitem.name), vmId: $($PSItem.vmId), ResourceGroup: $($PSItem.resourceGroup)"
            })
        return $untrackedHosts
    } else {
        return $false
    }
}

function Select-NewVMZones {
    <#
    .SYNOPSIS
        Takes a list of VMNames and selects an Azure availability zone for each one to ensure they are
        spread evenly across all zones. If the VM already exists the VMs current zone will be used.

        Assumes names in $VMNames are constructed from basenames plus rotation id and is therefore
        complete list of VMs to consider for zone selection of a host pool's VMs.
    .EXAMPLE
        Select-NewVMZones -VMNames $vmNames
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param (
        [Parameter(Mandatory = $true, HelpMessage = 'List of VM names to allocate')]
        [array]$VMNames,
        [Parameter(Mandatory = $false, HelpMessage = 'Array of zone numbers to use for new VMs')]
        [ValidateCount(1, 3)]
        [ValidateSet(1, 2, 3)]
        [array]$Zones = @(1, 2, 3)
    )

    $functionName = Get-PSFunctionName

    $selection = ('name', 'vmId', 'Zone', 'powerStateCode', 'provisioningState', 'resourceGroup', 'tags', 'vmResourceId')

    # Get existing VM details
    try {
        $provisionedVMs = Get-ProvisionedVmDetails -VMNames $VMNames | Select-Object $selection
    } catch {
        Write-Host "##[error]❗`t$($functionName): Failed to retrieve current VM details"
        Write-Host "##[error]❗`t$($functionName): ERROR: $_"
        throw 'Error from Get-ProvisionedVmDetails'
    }

    # Get current zone info / spread
    $zoneInfo = foreach ($zoneNum in $Zones) {
        [PSCustomObject]@{
            Zone  = $zoneNum
            Count = ($provisionedVMs | where-object { $PSItem.Zone -eq $zoneNum }).Count
        }
    }

    # Get list of new VMs if any
    $newVMNames = @()
    $newVMNames = $VMNames.Where({ $PSItem -inotin $provisionedVMs.name })

    # Allocate zones to new VMs
    if ([bool]$newVMNames) {
        $newVMs = $newVMNames.ForEach({
                [PSCustomObject]@{
                    $selection[0] = $PSItem
                    $selection[1] = 'none'
                    $selection[2] = (($zoneInfo | Sort-Object Count)[0].Zone).ToString()
                    $selection[3] = 'none'
                    $selection[4] = 'none'
                    $selection[5] = 'none'
                }
            (($zoneInfo | Sort-Object Count)[0]).Count++
            })
        # Passing to Select-Object to ensure consistent object type to pass to deployment
        $zoneResults = $newVMs + $provisionedVMs | Select-Object $selection
    } else {
        $zoneResults = $provisionedVMs | Select-Object $selection
    }

    return $zoneResults
}

function Get-VMRotationId {
    <#
    .SYNOPSIS
        Returns the vmRotationId tag of either the current or next rotation of VMs for the name host pool.
        The function will abort if the hosts do not all have matching values of vmRotationId.
    .EXAMPLE
        Get-VMRotationId -HostPoolName 'uks-int-vdi-avd-hpl-mult-099-02' -NextRotationId $true
        Gets the rotation id for the next rotation to use in re-imaging / patching processes
    .EXAMPLE
        Get-VMRotationId -HostPoolName 'uks-int-vdi-avd-hpl-mult-099-02'
        Gets the rotation id for the current rotation to use in adding or removing hosts from host pool
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true, HelpMessage = 'Name of the host pool to rotate')]
        [string]$HostPoolName,
        [Parameter(Mandatory = $false, HelpMessage = 'Gets next rotation id based on current VMs if true, otherwise return current id')]
        [bool]$NextRotationId = $false
    )

    $functionName = Get-PSFunctionName

    $rotations = @('A', 'B') # Must be an array of two only!

    try {
        $hostPoolVMs = Get-HostPoolVMDetails -HostPoolName $HostPoolName
    } catch {
        Write-Host "##[error]❗`t$($functionName): Failed to retrieve current VM details"
        Write-Host "##[error]❗`t$($functionName): ERROR: $_"
        throw 'Error from Search-AzGraphRestAPI'
    }

    $rotationIdGroup = $hostPoolVMs | Group-Object vmRotationId

    if (($rotationIdGroup.Name).Count -gt 1) {
        # Assume it is a mess and abort, subsequent code assumes one result
        Write-Host "##[error]❗`t$($functionName): More than one live rotation id found, clean-up required"
        Write-Host "##[debug]🐞`t$($functionName): Rotation id counts:"
        $rotationIdGroup | Select-Object @{n = 'vmRotationId'; e = { $PSItem.Name } }, Count | Write-Host
        Write-Host "##[debug]🐞`t$($functionName): Currently registered hosts:"
        $hostPoolVMs | Select-Object name, vmId, vmRotationId | Sort-Object vmRotationId | Write-Host
        throw 'Error finding next rotation id'
    } elseif (($rotationIdGroup.Name).Count -ne 1) {
        # If no registered hosts just return first rotation and ignore $NextRotationId
        Write-Host "##[debug]🐞`t$($functionName): No registered hosts found, choosing first rotation id"
        $rotationIdResult = $rotations[0]
    } else {
        switch ($NextRotationId) {
            # Assume either one or no results as function should have aborted earlier if not consistent
            $true {
                Write-Host "##[debug]🐞`t$($functionName): Current hosts look consistent, choosing next rotation id"
                $currentRotation = $rotationIdGroup[0].Name
                $rotationIdResult = $rotations.Where({ $PSItem -ine $currentRotation })
            }
            Default {
                Write-Host "##[debug]🐞`t$($functionName): Returning current rotation id"
                $rotationIdResult = $rotationIdGroup[0].Name
            }
        }
    }

    Write-Host "##[debug]🐞`t$($functionName): Chosen rotation id: $($rotationIdResult.ToUpper())"
    return $rotationIdResult.ToUpper()
}

function New-Password {
    [OutputType([securestring])]
    param (
        [Parameter(Mandatory = $false)]
        [int]$Length = 18
    )

    # Requires PowerShell 7 or later to for Get-Random to be cryptographically secure
    # https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/get-random?view=powershell-7.3

    $chars = "!@#$%^&*0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz".tochararray()
    $password = (($chars | Get-Random -Count $Length) -join '')

    return $password | ConvertTo-SecureString -AsPlainText -Force
}

function Test-SessionHostNames {
    param (
        [Parameter(Mandatory = $false, HelpMessage = 'Parameter files path')]
        [string]$ParametersPath = $(Join-Path -Path $env:BUILD_SOURCESDIRECTORY -ChildPath 'params')
    )

    $functionName = Get-PSFunctionName

    $allHostFiles = Get-ChildItem -Path $(Join-Path -Path $ParametersPath -ChildPath 'hosts' -AdditionalChildPath 'uks-EEE-vdi-avd-hpl-mult-*_hosts.json')
    $allHostFiles.ForEach({
            Write-Host "Checking $PSitem.Name"
        })

    $uniqueHostNames = $allHostNames = ($allHostFiles.ForEach({
                Get-Content $PSItem.FullName | ConvertFrom-Json -Depth 2
            })).baseHostnames | Select-Object -Unique

    # Find duplicate names in the host pool session host files
    $duplicateHostNames = (Compare-Object -ReferenceObject $uniqueHostNames -DifferenceObject $allHostNames).InputObject

    if ([bool]$duplicateHostNames) {
        Write-Host "##[error]❗`t$($functionName): Found duplicate hosts names in config files, aborting"
        Write-Host "##[debug]🐞`t$($functionName): Duplicate Names:"
        Write-Host $($duplicateHostNames -join "`n")
        throw 'Duplicates detected'
    } else {
        Write-Host "##[debug]🐞`t$($functionName): No duplicates host names found"
    }
}

function Get-MultiBaseHostNames {
    [CmdletBinding()]
    [OutputType([string[]])]
    param (
        [ValidateSet('001', '002', '003', '004', '005', '006', '007', '099', '999')]
        [string]$BusinessUnitId,
        [Parameter(Mandatory = $true, HelpMessage = 'Host pool Id')]
        [ValidateSet('01', '02', '03')]
        [string]$HostPoolId,
        [Parameter(Mandatory = $false, HelpMessage = 'Parameter files path')]
        [string]$ParametersPath = $(Join-Path -Path $env:BUILD_SOURCESDIRECTORY -ChildPath 'params')
    )

    $functionName = Get-PSFunctionName

    $hostsfile = Join-Path -Path $ParametersPath -ChildPath 'hosts' -AdditionalChildPath "uks-EEE-vdi-avd-hpl-mult-$($BusinessUnitId)-$($HostPoolId)_hosts.json"
    $baseHostnames = (Get-Content -Path $hostsfile | ConvertFrom-Json -Depth 100).baseHostnames

    return $baseHostnames
}

function Get-MultiVMNames {
    [CmdletBinding()]
    [OutputType([string[]])]
    param (
        [ValidateSet('001', '002', '003', '004', '005', '006', '007', '099', '999')]
        [string]$BusinessUnitId,
        [Parameter(Mandatory = $true, HelpMessage = 'Host pool Id')]
        [ValidateSet('01', '02', '03')]
        [string]$HostPoolId,
        [Parameter(Mandatory = $true, HelpMessage = 'Requested rotation id')]
        [string]$VMRotationId,
        [Parameter(Mandatory = $false, HelpMessage = 'Parameter files path')]
        [string]$ParametersPath = $(Join-Path -Path $env:BUILD_SOURCESDIRECTORY -ChildPath 'params')
    )

    $functionName = Get-PSFunctionName

    $baseHostnames = Get-MultiBaseHostNames -BusinessUnitId $BusinessUnitId -HostPoolId $HostPoolId -ParametersPath $ParametersPath

    $vmNames = $baseHostnames.ForEach({
            '{0}{1}' -f $PSItem, $VMRotationId
        })

    return $vmNames
}