//***** PARAMETERS *****//

@description('Object Id of AAD group to assign the role')
param p_GroupId string

@description('Environment names')
param p_envNames object

//***** VARIABLES *****//

//Definitiopn Id of 'Desktop Virtualization User' Builtin role
var v_roleId = '1d18fff3-a72a-46b5-b4a9-0b38a3cd7e63'
var v_appGroupName = p_envNames.appGroupName

//***** RESOURCES *****//

resource appGroup 'Microsoft.DesktopVirtualization/applicationgroups@2021-07-12' existing = {
  name: v_appGroupName
}

resource roleAssignement 'Microsoft.Authorization/roleAssignments@2022-04-01' =  {
  scope: appGroup
  name: guid(p_GroupId, appGroup.id, v_roleId)
  properties: {
    principalId: p_GroupId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', v_roleId)
  }
}

//***** OUTPUTS *****//

output appGroupName string = appGroup.name
output assignmentid string = roleAssignement.id
