//***** PARAMETERS *****//

@description('Environment names')
param p_envNames object

@description('The location where the resources will be deployed.')
param p_location string

@description('VM Name')
param p_TempVmName string

param p_setRedirCmd string

@description('Command to set NTFS permissions')
param p_setNTFSCmd string

@description('Azure tags to add to resources')
param p_tags object

@description('Deployment time, must be utcnow() and should not be supplied at runtime')
param p_deployTime string = utcNow()

//***** RESOURCES *****//

module mod_runCommands 'fslogix_vm_commands.bicep' = {
  name: 'mod-runCommands-${p_deployTime}'
  scope: resourceGroup(p_envNames.vmResourceGroupName)
  params: {
    p_location: p_location
    p_TempVmName: p_TempVmName
    p_setNTFSCmd: p_setNTFSCmd
    p_setRedirCmd: p_setRedirCmd
    p_tags: p_tags
  }
}
