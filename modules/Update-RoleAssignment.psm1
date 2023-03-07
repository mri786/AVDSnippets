<#
.Synopsis
   Function to update role assignments on Azure resources
.DESCRIPTION
   Function to update role assignments on Azure resources accepting an Add or Remove operation 
.EXAMPLE
   Update-VDIRoleAssign -azureResource myVM -aadObjectName firstname.surname@mydomain.com -azureRoleName "AVD Virtual Machine Admin Login" -roleOperation Add
   Adds the "AVD Virtual Machine Admin Login" role to device myVM for firstname.surname@mydomain.com
.LINK
    https://confluencelink
#>
function Update-RoleAssignment
{
    [CmdletBinding()]
    [Alias()]
    [OutputType([int])]
    Param
    (
        # Name of the Azure resource to update roles for
        [ValidateScript ({Start-AzGraphQuery -Query "Resources | where name == '$_'" -Silent})]
        [string]
        $azureResource,

        # The name of the Azure AD object to apply the role for
        [string]
        $aadObjectName,

        # Name of RBAC role to add
        [ValidateSet("AVD Virtual Machine Admin Login","Desktop Virtualization User")]
        [string]
        $azureRoleName,

        [ValidateSet("Add","Remove")]
        [string]
        $roleOperation
    )
    Begin
    {
        $FunctionStack = (Get-PSCallStack).FunctionName;$FunctionName = (($FunctionStack[$($FunctionStack.Count)..0] -Join "\") -Replace "\<.*?\>","").SubString(1)
        Write-Host "##[group]$($FunctionName): INFO - ******************** Enter function $FunctionName ********************"

        $currentContext = Get-AzContext

        $AllowedTypes = @{
            'AVD Virtual Machine Admin Login'= 'Microsoft.Compute/virtualMachines';
            'Desktop Virtualization User' = 'Microsoft.DesktopVirtualization/applicationgroups'
        }

    }
    Process
    {
        $exitCode = 0
        Write-Host "$($functionName): INFO - $roleOperation $aadObjectName to role $azureRoleName on resource $azureResource."

        Write-Host "$($functionName): INFO - Get details for $azureResource" -NoNewline
        $azureResourceDetails = Start-AzGraphQuery -Query "Resources | where name == '$azureResource'" -Silent

        if ($azureResourceDetails -eq $null) {
            Throw "$($functionName): FAILED - Resource $azureResource did not exist"
        } else {
            Write-Host "$($functionName): INFO - Resource $azureResource has been found"
            Write-Host "$($functionName): INFO - Resource Id : [$($azureResourceDetails.Id)]"
            Write-Host "$($functionName): INFO - Resource Subscription Id : [$($azureResourceDetails.subscriptionId)]"
            $resourceContext = get-azcontext -ListAvailable|?{$_.Subscription.Id -eq $azureResourceDetails.subscriptionId}
            Write-Host "$($FunctionName): INFO - Context : [$($resourceContext.Name)]"
        }
        
        Write-Host "$($functionName): INFO - Check if $azureRoleName is valid for $azureResource."
        if($AllowedTypes[$azureRoleName].ToUpper() -ne $azureResourceDetails.type.ToUpper()){
            Throw "$($functionName): FAILED - Invalid resource type, you can't grant '$azureRoleName' role to '$azureResource' which has a type of '$($azureResourceDetails.type)', the specified azureResource must have type of '$($AllowedTypes[$azureRoleName])' to apply role '$azureRoleName'."
        }

        Write-Host "$($functionName): INFO - Get AAD details for $aadObjectName" -NoNewline
        if($aadObjectName -like "*@*"){
            $aadObject = Get-AzADUser -UserPrincipalName $aadObjectName
        }else{
            $aadObject = Get-AzADGroup -displayName $aadObjectName
        }
        if($aadObject -eq $null){Throw "$($functionName): FAILED - Role $aadObjectName did not exist."}
        Write-Host ", id is $($aadObject.Id)."

        Write-Host "$($functionName): INFO - Get role details for $azureRoleName" -NoNewline
        $roleDetails = Get-AzRoleDefinition -Name $azureRoleName -AzContext $resourceContext
        if($roleDetails -eq $null){Throw "$($functionName): FAILED - Role $azureRoleName did not exist."}
        Write-Host ", id is $($roleDetails.Id)."

        Write-Host "$($functionName): INFO - Set up role params and get existing assignments" -NoNewline
        $roleParams = @{
            ObjectId = $aadObject.id
            RoleDefinitionId = $roleDetails.Id
            Scope = $azureResourceDetails.Id
        }
        $assignmentCheck = Get-AzRoleAssignment @roleParams -AzContext $resourceContext
        Write-Host ", $($assignmentCheck.count) assignment(s) found which are $($assignmentCheck.DisplayName -join ",")"

        try {
            Write-Host "$($functionName): INFO - $roleOperation '$azureRoleName' role for '$aadObjectName' on resource '$azureResource'"

            if($currentContext.subscription.Id -ne $azureResourceDetails.SubscriptionId){
                Write-Host "$($functionName): INFO - Switch to sub $($azureResourceDetails.SubscriptionId). Current subscription : $($(Get-AzContext).Subscription.Id)."
                $switchSub = Select-AzSubscription $azureResourceDetails.SubscriptionId
            }
            Write-Host "$($functionName): INFO - Current subscription : $($(Get-AzContext).Subscription.Name)"

            if($roleOperation -eq "Add") {
                if($assignmentCheck -eq $null){
                    $applyRoleResult = New-AzRoleAssignment @roleParams
                    write-host "$($functionName): INFO - Role added."
                } else {
                    write-host "$($functionName): INFO - Role already applied in desired state."
                }
            } else {
                if($assignmentCheck -ne $null){
                    $applyRoleResult = Remove-AzRoleAssignment @roleParams
                    write-host "$($functionName): INFO - Role removed."
                } else {
                    write-host "$($functionName): INFO - Role already applied in desired state."
                }
            }
        } catch {
            write-host "##[warning]$($functionName): FAILED - Role assignent failed with error: $($error[0].Exception.Message)."
            $exitCode++
        }

        Write-Host ""
        Write-Host "$($functionName): INFO - Exiting with ExitCode of $exitCode."
        write-output $exitCode
    }
    End
    {
        if($currentContext.subscription.Name -ne $($(Get-AzContext).Subscription.Name)){
            Write-Host "$($functionName): INFO - Switching back to $($currentContext.Subscription)"
            $switchSub = Select-AzSubscription -Subscription $currentContext.Subscription
            Write-Host "$($functionName): INFO - Subscription : $($(Get-AzContext).Subscription.Name)"
        }

        Write-Host "##[endgroup]$($FunctionName): INFO - ******************** Leave function $FunctionName ********************"
   }
}