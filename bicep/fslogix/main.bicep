targetScope = 'subscription'

//***** PARAMETERS *****//

@description('global deployment variables')
param p_globalVars object

@description('Environment deployment variables')
param p_envVars object

@description('Environment names')
param p_envNames object

@description('Host pool configuration object')
param p_hostPoolConfig object

@description('Hashtable of VmName:SecureString')
@secure()
param p_localAdminPassword string

@description('WSS Agent installation command')
param p_WSScmd string

@description('Azure tags to add to resources')
param p_tags object

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

module mod_fslogix_identity 'fslogix_identity.bicep' = {
  name: 'mod-fslogix-identity-${p_deployTime}'
  scope: resourceGroup(p_envNames.saResourceGroupName)
  params: {
    p_location: p_hostPoolConfig.location
    p_tags: v_tags
    p_TempVmName: p_globalVars.fslogix.tempVMName
  }
}

module mod_fslogix_smb_share 'fslogix_smb_share.bicep' = {
  name: 'mod-fslogix-smb-share-${p_deployTime}'
  scope: resourceGroup(p_envNames.saResourceGroupName)
  params: {
    p_profileShareName: p_envNames.fslogixProfileShare
    p_redirShareName: p_globalVars.fslogix.redirectionShareName
    p_fslogixStorageAccount: p_envNames.fslogixStorageAccount
  }
  dependsOn: [
    mod_fslogix_identity
  ]
}

module mod_fslogix_temp_vm 'fslogix_temp_vm.bicep' = {
  name: 'mod-fslogix-temp-vm-${p_deployTime}'
  scope: resourceGroup(p_envNames.vmResourceGroupName)
  params: {
    p_envNames: p_envNames
    p_envVars: p_envVars
    p_hostPoolConfig: p_hostPoolConfig
    p_localAdminPassword: p_localAdminPassword
    p_tags: v_tags
    p_TempVmName: p_globalVars.fslogix.tempVMName
    p_WSScmd: p_WSScmd
    p_identityId: mod_fslogix_identity.outputs.o_uaiId
  }
  dependsOn: [
    mod_fslogix_smb_share
  ]
}

module mod_fslogix_roles 'fslogix_roles.bicep' = {
  name: 'mod-fslogix-roles-${p_deployTime}'
  scope: resourceGroup(p_envNames.saResourceGroupName)
  params: {
    p_fslogixStorageAccount: p_envNames.fslogixStorageAccount
    p_identityPrincipalId: mod_fslogix_identity.outputs.o_uaiPrincipalId
  }
  dependsOn: [
    mod_fslogix_temp_vm
  ]
}
