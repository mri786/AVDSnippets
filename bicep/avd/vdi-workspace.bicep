targetScope = 'resourceGroup'

//***** PARAMETERS *****//

@description('Environment short name')
param p_envNames object

@description('Host pool configuration object')
param p_hostPoolConfig object

@description('Associate Application Groups to Workspace.')
param p_applicationGroupRef  array = []

@description('Azure tags to add to resources')
param p_tags object

//***** RESOURCES *****//get-con

resource Workspace 'Microsoft.DesktopVirtualization/workspaces@2021-07-12' = {
  name: p_envNames.workspaceName
  location: p_hostPoolConfig.location
  tags: p_tags
  properties: {
    applicationGroupReferences: p_applicationGroupRef 
    friendlyName: p_envNames.workspaceFriendlyName
  }
  
}
