targetScope = 'resourceGroup'

//***** PARAMETERS *****//

@description('VM identity principal id')
param p_identityPrincipalId string

@description('FSLogix storage account name')
param p_fslogixStorageAccount string

//***** VARIABLES *****//

var v_roleIds = [
  'a7264617-510b-434b-a828-9731dc254ea7'
  '81a9662b-bebf-436f-a333-f67b29880f12'
]

//***** RESOURCES *****//

resource storageAccount 'Microsoft.Storage/storageAccounts@2022-09-01' existing = {
  name: p_fslogixStorageAccount
}

resource roleAssignement 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (roleid, i) in v_roleIds: {
  scope: storageAccount
  name: guid(storageAccount.id, p_identityPrincipalId, '/providers/Microsoft.Authorization/roleDefinitions/${roleid}')
  properties: {
    principalId: p_identityPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleid)
    principalType: 'ServicePrincipal'
  }
}]
