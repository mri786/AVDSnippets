#Requires -Modules @{ModuleName="Az.Accounts"; ModuleVersion="2.11.0"}

function Add-AzureResourceTags {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory = $true, HelpMessage = 'Hashtable of tag names and values')]
        [hashtable]$Tags,
        [Parameter(Mandatory = $true, HelpMessage = 'Full resource id of Azure resource')]
        [hashtable]$ResourceId,
        [Parameter(Mandatory = $false, HelpMessage = 'Overwrite matching tags, default is $true')]
        [bool]$OverwriteMatching = $true
    )

    try {
        # Get current Azure resource tags
        $AzureResource = Get-AzResource -ResourceId $ResourceId -ErrorAction Stop

        # Add new tags to object
        switch ($Tags.keys) {
            {$AzureResource.Tags.ContainsKey($PSItem) -and $OverwriteMatching} {
                Write-Host "##[debug]🐞`t$($functionName): Updating tag: $($PSItem) with value: $($Tags.$PSItem), old value was: $($AzureResource.Tags.$PSItem)"
                $AzureResource.Tags.$PSItem = $Tags.$PSItem
            }
            {$AzureResource.Tags.ContainsKey($PSItem) -and !$OverwriteMatching} {
                Write-Host "##[debug]🐞`t$($functionName): Skipping existing tag: $($PSItem) with value: $($AzureResource.Tags.$PSItem)"
            }
            Default {
                Write-Host "##[debug]🐞`t$($functionName): Adding new tag: $($PSItem) with Value: $($Tags.$PSItem)"
                $AzureResource.Tags.Add($PSItem, $Tags.$PSItem)
            }
        }

        Set-AzResource -ResourceId $AzureResource.ResourceId -Tag $AzureResource.Tags -Force

    } catch [Microsoft.Azure.Commands.ResourceManager.Cmdlets.SdkClient.ResourceManagerCloudException] {
        if ($_.Exception.InnerException.Response.StatusCode -imatch 'NotFound') {
            Write-Host "##[warning]❓`t$($functionName): Resource not found"
            Write-Host "##[warning]❓`t$($_.Exception.InnerException.Message)"
            return 'NotFound'
        } else {
            Write-Host "##[error]❗`t$($functionName): Error returned from Azure Resource Manager:"
            Write-Host "##[error]❗`t$($_.Exception.InnerException.Message)"
            throw 'Error returned from Azure Resource Manager'
        }
    } catch {
        Write-Host "##[error]❗`t$($functionName): Error setting tags"
        Write-Host "##[error]❗`t$($_.Exception.InnerException.Message)"
        throw 'Unhandled error setting tags'
    }

    return $AzureResource.Tags

}
