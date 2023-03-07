targetScope = 'subscription'

//***** PARAMETERS *****//

@description('Environment names')
param p_envNames object

@description('global deployment variables')
param p_globalVars object

@description('Environment deployment variables')
param p_envVars object

@description('Host pool configuration object')
param p_hostPoolConfig object

@description('Array of host object details')
param p_hosts array

@description('Current host pool registration token')
@secure()
param p_hplToken string

@description('Hashtable of VmName:SecureString')
@secure()
param p_localAdminPasswords object

@description('Whether to install WSS agent')
param p_installWSS bool = true

@description('WSS Agent installation command')
param p_WSScmd string

@description('Whether to initiate host pool registration')
param p_hostPoolRegistration bool

@description('Azure tags to add to resources')
param p_tags object

@description('Resource group scoped role assignment details')
param p_rgRoleAssignments array

@description('Deployment time, must be utcnow() and should not be supplied at runtime')
param p_deployTime string = utcNow()

//***** VARIABLES *****//

var v_tags = union(p_tags, p_globalVars.tags, {
    buildMedia: p_hostPoolConfig.sessionHosts.buildImage
    buildMediaVer: p_hostPoolConfig.sessionHosts.buildImageVer
    securityClassification: p_hostPoolConfig.sessionHosts.securityClassification
    businessUnitName: p_hostPoolConfig.businessUnitName
  })

//***** RESOURCES *****//

module mod_vdi_dcr 'vdi_dcr.bicep' = {
  name: 'mod-vdi-dcr-${p_deployTime}'
  scope: resourceGroup(p_envVars.avdBrokerSubscriptionId, p_envVars.avdResourceGroup)
  params: {
    p_dcrRuleName: p_envNames.dcrRuleName
    p_LAWResourceId: p_envVars.LAWResourceId
    p_location: p_hostPoolConfig.location
    p_tags: v_tags
  }
}

module mod_vdi_asg 'vdi_asg.bicep' = {
  name: 'mod-vdi-asg-${p_deployTime}'
  scope: resourceGroup(p_envNames.vnetResourceGroupName)
  params: {
    p_asgName: p_envNames.asgName
    p_location: p_hostPoolConfig.location
    p_tags: v_tags
  }
}

module mod_vdi_rg_roles 'vdi_rg_roles.bicep' = [for role in p_rgRoleAssignments: {
  name: 'mod_vdi_rg_roles-${p_deployTime}'
  scope: resourceGroup(role.resourceGroup)
  params: {
    p_GroupId: role.groupId
    p_RoleId: role.roleId
  }
}]

@batchSize(10)
module mod_vdi_vm 'vdi_vm.bicep' = [for (vm, i) in p_hosts: {
  name: 'mod-vdi-vm-${vm.name}-${p_deployTime}'
  scope: resourceGroup(p_envNames.vmResourceGroupName)
  params: {
    p_WSScmd: p_WSScmd
    p_hostPoolRegistered: vm.hostPoolRegistered
    p_globalVars: p_globalVars
    p_envVars: p_envVars
    p_envNames: p_envNames
    p_hostPoolConfig: p_hostPoolConfig
    p_hostPoolName: p_envNames.hostPoolName
    p_hplToken: p_hplToken
    p_hybridJoin: p_hostPoolConfig.sessionHosts.haadj
    p_installWSS: p_installWSS
    p_localAdminPassword: p_localAdminPasswords[vm.name]
    p_tags: v_tags
    p_vmName: vm.name
    p_vmId: vm.vmId
    p_vmZone: vm.zone
    p_hostPoolRegistration: p_hostPoolRegistration
    p_dcrRuleName: mod_vdi_dcr.outputs.o_dcrRuleName
    p_dcrRuleId: mod_vdi_dcr.outputs.o_dcrRuleId
    p_asgId: mod_vdi_asg.outputs.asgId
  }
}]
