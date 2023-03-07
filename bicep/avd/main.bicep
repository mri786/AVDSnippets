targetScope = 'resourceGroup'

//***** PARAMETERS *****//

@description('Environment short name')
param p_envNames object

@description('global deployment variables')
param p_globalVars object

@description('Host pool configuration object')
param p_hostPoolConfig object

@description('Does Workspace already exist.')
param p_ExistsWorkspace bool

@description('Hostpool RDP properties')
param p_customRdpProperty string

@description('Object Id of AAD group to assign the role')
param p_groupId string

@description('Azure tags to add to resources')
param p_tags object

@description('Deployment time, must be utcnow() and should not be supplied at runtime')
param p_deployTime string = utcNow()

//***** VARIABLES *****//

var v_tags = union(p_tags, p_globalVars.tags, {
    securityClassification: p_hostPoolConfig.sessionHosts.securityClassification
    businessUnitName: p_hostPoolConfig.businessUnitName
  })

//***** RESOURCES *****//

module mod_vdi_workspace 'vdi-workspace.bicep' = if(!p_ExistsWorkspace) {
  name: 'mod_vdi_workspace-${p_deployTime}'
  params: {
    p_hostPoolConfig : p_hostPoolConfig
    p_envNames: p_envNames
    p_tags: v_tags
  }
}

resource Workspace 'Microsoft.DesktopVirtualization/workspaces@2021-07-12' existing = {
  name: p_envNames.workspaceName
}

module mod_vdi_workspace_update 'vdi-workspace.bicep' = if(p_ExistsWorkspace) {
  name: 'mod_vdi_workspace_update-${p_deployTime}'
  params: {
    p_hostPoolConfig : p_hostPoolConfig
    p_envNames: p_envNames
    p_tags: v_tags
    p_applicationGroupRef : ((p_ExistsWorkspace)) ? Workspace.properties.applicationGroupReferences : []
  }
}

module mod_vdi_hostpool 'vdi-hostpool.bicep' = {
  name: 'mod_vdi_hostpool-${p_deployTime}'
  params: {
    p_customRdpProperty: p_customRdpProperty
    p_hostPoolConfig : p_hostPoolConfig
    p_envNames: p_envNames
    p_tags: v_tags
  }
}

module mod_vdi_appgroup 'vdi-appgroup.bicep' = {
  name: 'mod_vdi_appgroup-${p_deployTime}'
  params: {
    p_hostPoolConfig : p_hostPoolConfig
    p_envNames: p_envNames
    p_tags: v_tags
  }
  dependsOn: [
    mod_vdi_workspace
    mod_vdi_hostpool
  ]
}

module mod_vdi_ap_roles 'vdi-appgrouproles.bicep' = {
  name: 'mod_vdi_ap_roles-${p_deployTime}'
  params: {
    p_GroupId: p_groupId
    p_envNames: p_envNames
  }
  dependsOn: [
    mod_vdi_appgroup
  ]
}

//***** OUTPUTS *****//

output ExistingWorkspace bool = p_ExistsWorkspace
output ExistingWorkspace2 string = ((p_ExistsWorkspace)) ? 'Workspace already exists' : 'New Workspace will be created'
output ExistingWorkspaceAppGroupRefs array = ((p_ExistsWorkspace)) ? Workspace.properties.applicationGroupReferences : []
