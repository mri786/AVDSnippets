<#
.Synopsis
   Function that deletes AVD Hostpool, Appgroup and Workspace objects.
.DESCRIPTION
   This function leverages Azure Graph API (and other Azure PSH cmdlets) to identify the correct AVD platform subscription per environment
   The function requires a hostpool name object to be supplied on the pipeline that requires deletion.
   The function can also delete the associated workspace object if required.
   The function can force deletion of hostpool and workspace objects if required i.e. host pools registered into hostpool or more than 1 appgroup associated with the workspace.
.EXAMPLE
   Remove-AVDHostpool -hostPoolName uks-idv-vdi-avd-hpl-pers-001-01 -location UKSOUTH -forceupdate $false -env idv -deleteworkspace $false
   Hostpool - uks-idv-vdi-avd-hpl-pers-001-01 will be deleted only if it has no session hosts assigned and will not delete the associated workspace if detected.
.EXAMPLE
   Remove-AVDHostpool -hostPoolName uks-idv-vdi-avd-hpl-pers-001-01 -location UKSOUTH -forceupdate $true -env idv -deleteworkspace $true
   Hostpool - uks-idv-vdi-avd-hpl-pers-001-01 will be deleted even if it has session hosts assigned and the associated workspace will be deleted regardless of the number of appgroup associations.
.LINK
    https://confluencelink
#>
function Remove-AVDHostpool {

    [CmdletBinding()]

    param (
        [Parameter(HelpMessage = "Host pool name")]
        [string]
        $hostPoolName,
        [Parameter(HelpMessage = "Location for host pool")]
        [string]
        $location,
        [Parameter(HelpMessage = "Force update")]
        $forceUpdate = $false,
        [Parameter(HelpMessage = "AVD Environment")]
        $env,
        [Parameter(HelpMessage = "Delete associated workspace object?")]
        $DeleteWorkspace = $false
    )

    Begin
    {
        
        $functionStack = (Get-PSCallStack).functionName;$functionName = (($functionStack[$($functionStack.Count-4)..0] -Join "\") -Replace "\<.*?\>","").SubString(1)
        Write-Host "$($functionName): INFO - ******************** Enter function $functionName ********************"

        $ModuleCheck = get-module "Az.ResourceGraph" -ea 0
    
        if($Null -eq $ModuleCheck -or ($ModuleCheck.Version.Major -lt 1 -and $ModuleCheck.Version.Minor -lt 8)){
             Install-Module -Name "Az.ResourceGraph" -Repository "PSGallery" -MinimumVersion "0.8.0" -AllowClobber -Confirm:$false -Force
        }
    }

    Process
    {

        $EXITCODE = 0

        # get subscription ID for AVD by environment
        
        Write-Host "$($functionName): INFO - obtaining subscription resources"
        write-host "resourcecontainers | where type == 'microsoft.resources/subscriptions/resourcegroups' and name contains 'uks-$env-vdi-avd-rsg'"

        $AVDSUBRESOURCE = Search-AzGraph -Query "resourcecontainers | where type == 'microsoft.resources/subscriptions/resourcegroups' and name contains 'uks-$env-vdi-avd-rsg'"
                 
        if ($AVDSUBRESOURCE.count -eq 0){
             
            Write-Host "$($functionName): INFO - Unable to locate AVD subscription resources for the $ENV environment in Azure."
            Write-Host "$($functionName): INFO - Cannot continue with an AVD object creation."
             
            $ExitCode = 1
            RETURN
             
        }

        # Get Az context and switch to it
     
        $currentsubcontext = get-azcontext
     
        # switch to AVD subscription context where the AVD objects reside
     
        try {
    
            Write-Host "$($FunctionName): INFO - Current subcription scope is $($currentsubcontext.Subscription.SubscriptionId)."
            Write-Host "$($FunctionName): INFO - Switching to AVD scope $($AVDSUBRESOURCE[0].subscriptionid)."
     
            $newcontext = Select-AzSubscription -SubscriptionId $AVDSUBRESOURCE[0].subscriptionid -ErrorAction stop
     
        }
        catch {
     
             Write-Host "$FunctionName : ERROR - Unable to switch to AVD subcription $($AVDSUBRESOURCE[0].subscriptionid)."
             write-host $_
     
             # Exit function
     
             RETURN
     
        }

        # Check if workspace already exists in order to reapply appgroup property references
        Write-Host "$($functionName): INFO - Checking if hostpool $hostpoolname already exists"

        $hostpoolobj = Get-AzWvdHostPool -SubscriptionId $AVDSUBRESOURCE.subscriptionID -Name $hostPoolName -ResourceGroupName $AVDSUBRESOURCE.resourcegroup
         
        if ($hostpoolobj.count -gt 0){
    
            #  Check hostpool exists
            Write-host "$($functionName): INFO - Detected existing hostpool - $($hostpoolobj.name)"
    
        }
        else{
    
            write-host "$($functionName): Error: Cannot locate hostpool $hostpoolname"
            write-host "$($functionName): Error: Cannot continue"

            $EXITCODE = 1
            RETURN $EXITCODE
    
        }

        # check linked workspace

        Write-host "$($functionName): INFO - Discovering Application Group associated with $($hostpoolobj.name)."

        # Get AppGroup RID for hostpool
        $appgroupobj = Get-AzWvdApplicationGroup -SubscriptionId $AVDSUBRESOURCE.subscriptionID | where-object {$_.Id -eq "$(($hostpoolobj).ApplicationGroupReference)"}

        Write-host "$($functionName): INFO - Application Group associated with $($hostpoolobj.name) is $($appgroupobj.name)."
        

        # If workspace is also to be deleted, then identify associated workspace for the appgroup and delete

        If($DeleteWorkspace -eq $true){

            Write-host "$($functionName): INFO - Deletion of associated workspace object is $DeleteWorkspace"
            Write-host "$($functionName): INFO - Discovering if a Workspace is associated with $($appgroupobj.name)."
            
            # Get Workspace RID for AppGroup
            $LinkedWorkspaceObj = Get-AzWvdWorkspace -SubscriptionId $AVDSUBRESOURCE.subscriptionID -ResourceGroupName $AVDSUBRESOURCE.Resourcegroup | where-object {$_.Id -eq "$(($appgroupobj.WorkspaceArmPath))"}

            Write-host "$($functionName): INFO - Workspace associated with $($appgroupobj.name) is $($LinkedWorkspaceObj.Name)."

            # Delete workspace

            if (($LinkedWorkspaceObj.ApplicationGroupReference).count -eq 1){
    
                Write-host "$($functionName): Detected $(($LinkedWorkspaceObj.ApplicationGroupReference).count) Application group references"
                Write-host "$($LinkedWorkspaceObj.ApplicationGroupReference)"
                Write-host "$($functionName): Removing workspace $($LinkedWorkspaceObj.Name) object"

                try {
                    
                    $removeworkspaceobj = Remove-AzWvdWorkspace -SubscriptionId $AVDSUBRESOURCE.subscriptionID -ResourceGroupName $AVDSUBRESOURCE.Resourcegroup `
                    -Name $LinkedWorkspaceObj.Name -ErrorAction STOP
                }
                catch {
                    
                    write-host "$($functionName): ERROR - There was an error removing $($LinkedWorkspaceObj.Name). Cannot continue with removal of AVD objects."
                    write-error $_
            
                    $EXITCODE = 1
                    RETURN $EXITCODE
                }

                Write-host "$($functionName): INFO - Deleted $($LinkedWorkspaceObj.Name)."
            }
            
            # If more than 1 appgroup reference then only continue only if force is enabled

            if (($LinkedWorkspaceObj.ApplicationGroupReference).count -gt 1 -and $forceUpdate -eq $true){
                    
                Write-host "$($functionName): Detected $(($LinkedWorkspaceObj.ApplicationGroupReference).count) Application group references and forceupdate is $forceupdate"
                Write-host "$($LinkedWorkspaceObj.ApplicationGroupReference)"
                Write-host "$($functionName): Workspace $($LinkedWorkspaceObj.Name) will be deleted"

                try {
                    
                    $removeworkspaceobj = Remove-AzWvdWorkspace -SubscriptionId $AVDSUBRESOURCE.subscriptionID -ResourceGroupName $AVDSUBRESOURCE.Resourcegroup `
                    -Name $LinkedWorkspaceObj.Name -ErrorAction STOP
                }
                catch {
                    
                    write-host "$($functionName): ERROR - There was an error removing $($LinkedWorkspaceObj.Name). Cannot continue with removal of AVD objects."
                    write-error $_
            
                    $EXITCODE = 1
                    RETURN $EXITCODE
                }

                Write-host "$($functionName): INFO - Deleted $($LinkedWorkspaceObj.Name)."

            }
            elseif (($LinkedWorkspaceObj.ApplicationGroupReference).count -gt 1 -and $forceUpdate -eq $false){
                    
                Write-host "$($functionName): Detected $(($LinkedWorkspaceObj.ApplicationGroupReference).count) Application group references and forceupdate is $forceupdate"
                Write-host "$($LinkedWorkspaceObj.ApplicationGroupReference)"
                Write-host "$($functionName): Workspace $($LinkedWorkspaceObj.Name) will NOT be deleted"

            }
            Else{

                Write-host "$($functionName): No Workspace reference found for $($appgroupobj.Name)"
                Write-host "$($functionName): No associated workspace object to delete."

            }

        }

        # delete appgroup

        Write-host "$($functionName): INFO - Now deleting $($appgroupobj.name)."

        try{
            
            $removeappgroupobj = Remove-AzWvdApplicationGroup -SubscriptionId $AVDSUBRESOURCE.subscriptionID -ResourceGroupName $AVDSUBRESOURCE.resourcegroup `
            -Name $appgroupobj.Name 
        }
        catch{
            
            write-host "$($functionName): ERROR - There was an error removing $($appgroupobj.Name). Cannot continue with removal of AVD objects."
            write-error $_
            
            $EXITCODE = 1
            RETURN $EXITCODE

        }
        
        # delete hostpool

        Write-host "$($functionName): INFO - Deleted $($appgroupobj.name)."
        Write-host "$($functionName): INFO - Now deleting $($hostpoolobj.Name)."

        try{
            
            $removeappgroupobj = Remove-AzWvdHostPool -SubscriptionId $AVDSUBRESOURCE.subscriptionID -ResourceGroupName $AVDSUBRESOURCE.resourcegroup `
            -Name $hostpoolobj.Name -Force

        }
        catch{
            
            write-host "$($functionName): ERROR - There was an error removing $($hostpoolobj.Name). Cannot continue with removal of AVD objects."
            write-error $_
            
            $EXITCODE = 1
            RETURN $EXITCODE

        }

        Write-host "$($functionName): INFO - deleted $($hostpoolobj.Name)."
        
        Write-Host "$($functionName): INFO - Returning exit code $exitcode"
            
            RETURN $EXITCODE
    
    }
    
    End
    {

        Write-Host "$($functionName): INFO - ******************** Leave function $functionName ********************"

    }
 }