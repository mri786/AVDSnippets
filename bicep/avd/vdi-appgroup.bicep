targetScope = 'resourceGroup'

//***** PARAMETERS *****//

@description('Environment names')
param p_envNames object

@description('Host pool configuration object')
param p_hostPoolConfig object

param p_deployTime string = utcNow()

@description('Azure tags to add to resources')
param p_tags object

//***** VARIABLES *****//

var AddappGroup = [appGroup.id]
var ExistingAppGroupRefs = Workspace.properties.applicationGroupReferences
var AppGroupCheck = contains(string(ExistingAppGroupRefs), p_envNames.appGroupName)
var applicationGroupReferencesArr = (AppGroupCheck) ? ExistingAppGroupRefs : union(Workspace.properties.applicationGroupReferences,array(AddappGroup))

//***** RESOURCES *****//

resource hostpoolName_resource 'Microsoft.DesktopVirtualization/hostPools@2022-04-01-preview' existing = {
  name: p_envNames.hostPoolName
}

resource appGroup 'Microsoft.DesktopVirtualization/applicationgroups@2021-07-12' = {
  name: p_envNames.appGroupName
  location: p_hostPoolConfig.location
  tags: p_tags
  properties: {
    hostPoolArmPath: hostpoolName_resource.id
    friendlyName: p_envNames.appGroupFriendlyName
    description: p_envNames.appGroupDescription
    applicationGroupType: p_hostPoolConfig.appGroup.type
  }
}

resource Workspace 'Microsoft.DesktopVirtualization/workspaces@2021-07-12' existing = {
  name: p_envNames.workspaceName
}

module mod_vdi_appGroupRef 'vdi-workspace.bicep' = {
  name: 'mod_vdi_appGroupRef-${p_deployTime}'
  params: {
    p_envNames: p_envNames
    p_hostPoolConfig: p_hostPoolConfig
    p_tags: p_tags
    p_applicationGroupRef: applicationGroupReferencesArr
  }
}

//***** OUTPUTS *****//

output IsAppGroupAssignedtoWorkspace bool = AppGroupCheck
output UpdateAppRefs array = applicationGroupReferencesArr
