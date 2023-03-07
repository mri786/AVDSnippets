targetScope = 'resourceGroup'

//***** PARAMETERS *****//

@description('Azure location')
param p_location string

@description('Azure tags to add to resources')
param p_tags object

@description('Name of VM')
param p_vmName string

@description('AD domain FQDN to join computer')
param p_ADDomain string

@description('AD OU in which to create computer account')
param p_ouPath string

@description('VM admin username')
@secure()
param p_adJoinUser string

@description('VM admin password')
@secure()
param p_adJoinPassword string

//***** RESOURCES *****//

resource domain_join 'Microsoft.Compute/virtualMachines/extensions@2022-03-01' = {
  name: '${p_vmName}/ADDomainJoin'
  location: p_location
  tags: p_tags
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'JsonADDomainExtension'
    typeHandlerVersion: '1.3'
    settings: {
      name: p_ADDomain
      ouPath: p_ouPath
      user: p_adJoinUser
      restart: true
      options: '3'
      NumberOfRetries: '4'
      RetryIntervalInMilliseconds: '30000'
    }
    protectedSettings: {
      password: p_adJoinPassword
    }
  }
}
