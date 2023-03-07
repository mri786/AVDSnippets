#Requires -Modules @{ModuleName="Az.Accounts"; ModuleVersion="2.11.0"}

function Search-AzGraphRestAPI {
    [CmdletBinding()]
    [OutputType([object])]
    param (
        [Parameter(Mandatory = $true, HelpMessage = 'Name of the host pool to which the vms are being deployed')]
        [string]$Query,
        [Parameter(Mandatory = $false, HelpMessage = 'Maximum results to return, will return all results if not specified')]
        [ValidateRange(1, 100000)]
        [int]$Limit,
        [Parameter(Mandatory = $false, HelpMessage = 'Specify supported API version')]
        [ValidateSet('2021-03-01', '2020-04-01-preview')]
        [string]$APIVersion = '2021-03-01'
    )

    $functionName = Get-PSFunctionName

    # Determine required API loops
    [int]$apiLimit = 1000
    switch ($Limit) {
        { ([bool]$Limit) -and ($Limit -le $apiLimit) } {
            $responseLimit = $Limit
        }
        { ([bool]$Limit) -and ($Limit -gt $apiLimit) } {
            [int]$fullLoops = $Limit / $apiLimit
            [int]$lastLoop = $Limit % $apiLimit
            $responseLimit = 'Remainder'
        }
        Default { $responseLimit = $apiLimit }
    }

    # Set up variables for API calls
    [uri]$armUri = 'https://management.azure.com/providers/Microsoft.ResourceGraph/resources?api-version={0}' -f $APIVersion
    $header = @{
        Authorization  = 'Bearer {0}' -f (Get-AzAccessToken).Token
        'Content-Type' = 'application/json'
    }
    $skipToken = $null
    $result = @()
    $loop = 0

    # Get results from API
    do {
        $loop++
        Write-Host "##[debug]🐞`t$($functionName): Getting query results...loop: $($loop)"

        switch ($skipToken) {
            $null {
                $options = @{
                    '$top'             = switch ($responseLimit) {
                        { ($PSItem -eq 'Remainder') -and ($loop -le $fullLoops) } { $apiLimit }
                        { ($PSItem -eq 'Remainder') -and ($loop -gt $fullLoops) } { $lastLoop }
                        Default { $responseLimit }
                    }
                    '$skip'            = 0
                    resultFormat       = 'objectArray'
                    allowPartialScopes = $false
                }
            }
            Default {
                $options = @{
                    resultFormat       = 'objectArray'
                    allowPartialScopes = $false
                    '$skipToken'       = $skipToken
                }
            }
        }

        $body = @{
            subscriptions = (Get-AzSubscription).Id
            query         = $Query
            options       = $options
        } | ConvertTo-Json

        $graphParams = @{
            Uri     = $armUri.AbsoluteUri
            Method  = 'Post'
            Headers = $header
            Body    = $body
        }

        try {
            $response = Invoke-RestMethod @graphParams
        } catch {
            Write-Host "##[error]❗`t$($functionName): ERROR: $_"
            throw 'Error running Azure Graph query'
        }

        $result += $response.data
        $skipToken = $response.'$skipToken'
    } while (![string]::IsNullOrEmpty($skipToken) -and (![bool]$Limit -or ($result.count -lt $Limit)))

    Write-Host "##[debug]🐞`t$($functionName): Finished looping through results, returning result..."
    return $result
}

function Get-MSGraphAADGroup {
    param (
        [Parameter(Mandatory = $true, HelpMessage = 'Name of the AAD group to get')]
        [string]$GroupName,
        [Parameter(Mandatory = $false, HelpMessage = 'Specify supported API version')]
        [ValidateSet('v1.0', 'beta')]
        [string]$APIVersion = 'beta'
    )

    $functionName = Get-PSFunctionName

    Write-Host "##[debug]🐞`t$($functionName):Getting details of AAD Group: $($GroupName)"

    [uri]$msGraphUri = 'https://graph.microsoft.com/{0}/groups?$filter=displayName eq ''{1}''' -f $APIVersion, $GroupName
    $header = @{
        Authorization  = 'Bearer {0}' -f (Get-AzAccessToken -ResourceTypeName 'MSGraph').Token
        'Content-Type' = 'application/json'
    }

    $graphParams = @{
        Uri     = $msGraphUri.AbsoluteUri
        Method  = 'Get'
        Headers = $header
    }

    try {
        $response = Invoke-RestMethod @graphParams
    } catch {
        Write-Host "##[error]❗`t$($functionName): ERROR: $_"
        throw 'Error querying MS Graph'
    }

    return $response.value
}