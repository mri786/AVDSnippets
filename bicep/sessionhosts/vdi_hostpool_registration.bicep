//***** PARAMETERS *****//

@description('Azure location')
param p_location string

@description('URL to download AVD Agent')
param p_avdAgentLocation string

@description('Name of host pool associated with VM')
param p_hostPoolName string

@description('Azure tags to add to resources')
param p_tags object

@description('Current host pool registration token')
@secure()
param p_hplToken string

@description('Name of VM')
param p_vmName string

//***** RESOURCES *****//

resource virtualMachine 'Microsoft.Compute/virtualMachines@2022-03-01' existing = {
  name: p_vmName

}

resource register_host 'Microsoft.Compute/virtualMachines/extensions@2022-03-01' = {
  name: 'AVDHostPoolRegistration'
  location: p_location
  tags: p_tags
  parent: virtualMachine
  properties: {
    publisher: 'Microsoft.Powershell'
    type: 'DSC'
    typeHandlerVersion: '2.73'
    autoUpgradeMinorVersion: true
    settings: {
      modulesUrl: p_avdAgentLocation
      configurationFunction: 'Configuration.ps1\\AddSessionHost'
      properties: {
        hostPoolName: p_hostPoolName
        registrationInfoToken: p_hplToken
      }
    }
  }
}
