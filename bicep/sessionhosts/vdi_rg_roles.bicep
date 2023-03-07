//***** PARAMETERS *****//

@description('Object Id of AAD group to assign the role')
param p_GroupId string

@description('Definition Id of custom AVD Virtual Machine User Login role to assign')
param p_RoleId string

//***** RESOURCES *****//

resource assign_role 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(p_GroupId, resourceGroup().id, p_RoleId)
  properties: {
    principalId: p_GroupId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', p_RoleId)
  }
}
