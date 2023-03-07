//***** PARAMETERS *****//

@description('global deployment variables')
param p_globalVars object

@description('Environment deployment variables')
param p_envVars object

@description('Environment short name')
param p_envNames object

@description('Host pool configuration object')
param p_hostPoolConfig object

@description('Name of host pool associated with VM')
param p_hostPoolName string

@description('Name of VM')
param p_vmName string

@description('vmId attribute to check for existing VM')
param p_vmId string

@description('Availability zone in which to deploy VM')
param p_vmZone string

@description('Whether the VM is already registered with the host pool')
param p_hostPoolRegistered bool

@description('Whether to initiate host pool registration')
param p_hostPoolRegistration bool = false

@description('Current host pool registration token')
@secure()
param p_hplToken string

@description('Hashtable of VmName:SecureString')
@secure()
param p_localAdminPassword string

@description('Whether to initiate hybrid AD join')
param p_hybridJoin bool

@description('Whether to install WSS agent')
param p_installWSS bool

@description('WSS Agent installation command')
param p_WSScmd string

@description('Azure tags to add to resources')
param p_tags object

@description('Name of DCR rule to associate with VM')
param p_dcrRuleName string

@description('Id of DCR rule to associate with VM')
param p_dcrRuleId string

@description('Resource Id of Application Security Group to associate with VM')
param p_asgId string

@description('Deployment time, must be utcnow() and should not be supplied at runtime')
param p_deployTime string = utcNow()

//***** RESOURCES *****//

resource vnet 'Microsoft.Network/virtualNetworks@2022-01-01' existing = {
  name: p_envNames.vnetName
  scope: resourceGroup(p_envNames.vnetResourceGroupName)
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2022-01-01' existing = {
  name: p_envNames.subnetName
  parent: vnet
}

resource avdKV 'Microsoft.KeyVault/vaults@2021-10-01' existing = {
  name: p_envVars.avdKeyVaultName
  scope: resourceGroup(p_envVars.avdBrokerSubscriptionId, p_envVars.avdKeyVaultResourceGroup)
}

// Generate new KEK for Azure Disk Encryption
module mod_vdi_ade_key 'vdi_ade_key.bicep' = {
  name: 'mod-vdi-ade-key-${p_vmName}-kek-${p_deployTime}'
  scope: resourceGroup(p_envNames.keyVaultResourceGroupName)
  params: {
    p_newKey: toLower(p_vmId) == toLower(virtualMachine.properties.vmId) ? false : true
    p_keyName: '${p_vmName}-${virtualMachine.properties.vmId}-kek'
    p_kvName: p_envNames.keyVaultName
    p_tags: p_tags
  }
}

// Create network interfaces
resource nic 'Microsoft.Network/networkInterfaces@2022-01-01' = {
  name: '${p_vmName}-nic'
  location: p_hostPoolConfig.location
  tags: p_tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig'
        properties: {
          applicationSecurityGroups: [
            {
              id: p_asgId
            }
          ]
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: subnet.id
          }
        }
      }
    ]
    enableIPForwarding: false
  }
}

// Create session host VMs
resource virtualMachine 'Microsoft.Compute/virtualMachines@2022-03-01' = {
  name: p_vmName
  location: p_hostPoolConfig.location
  tags: p_tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    licenseType: 'Windows_Client'
    hardwareProfile: {
      vmSize: p_hostPoolConfig.sessionHosts.vmSku
    }
    osProfile: {
      computerName: p_vmName
      adminUsername: p_hostPoolConfig.sessionHosts.localAdminUsername
      adminPassword: p_localAdminPassword
      windowsConfiguration: {
        enableAutomaticUpdates: false
        timeZone: p_hostPoolConfig.sessionHosts.timeZone
        patchSettings: {
          patchMode: 'Manual'
        }
        provisionVMAgent: true
      }
      allowExtensionOperations: true
    }
    storageProfile: {
      osDisk: {
        name: '${p_vmName}-osdisk'
        managedDisk: {
          storageAccountType: p_hostPoolConfig.sessionHosts.vmDiskType
        }
        diskSizeGB: p_hostPoolConfig.sessionHosts.vmDiskSizeGb
        osType: 'Windows'
        createOption: 'FromImage'
        deleteOption: 'Delete'
      }
      imageReference: {
        id: p_hostPoolConfig.sessionHosts.buildImageVer == 'latest' ? resourceId(
          p_envVars.buildACGSubId, p_envVars.buildACGResourceGroup, 'Microsoft.Compute/galleries/images', p_envVars.buildACG, p_hostPoolConfig.sessionHosts.buildImage
        ) : resourceId(
          p_envVars.buildACGSubId, p_envVars.buildACGResourceGroup, 'Microsoft.Compute/galleries/images/versions', p_envVars.buildACG, p_hostPoolConfig.sessionHosts.buildImage, p_hostPoolConfig.sessionHosts.buildImageVer)
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
          properties: {
            deleteOption: 'Delete'
          }
        }
      ]
    }
    securityProfile: {
      uefiSettings: {
        secureBootEnabled: true
        vTpmEnabled: true
      }
      securityType: 'TrustedLaunch'
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
  zones: [
    p_vmZone
  ]
}

// Enable Azure Disk Encryption
resource ade 'Microsoft.Compute/virtualMachines/extensions@2022-03-01' = {
  name: 'AzureDiskEncryption'
  location: p_hostPoolConfig.location
  tags: p_tags
  parent: virtualMachine
  properties: {
    publisher: 'Microsoft.Azure.Security'
    type: 'AzureDiskEncryption'
    typeHandlerVersion: '2.2'
    autoUpgradeMinorVersion: true
    forceUpdateTag: '1.0'
    settings: {
      EncryptionOperation: 'EnableEncryption'
      KeyVaultURL: mod_vdi_ade_key.outputs.kvUrl
      KeyVaultResourceId: mod_vdi_ade_key.outputs.kvId
      KeyEncryptionKeyURL: mod_vdi_ade_key.outputs.kekUrl
      KekVaultResourceId: mod_vdi_ade_key.outputs.kvId
      KeyEncryptionAlgorithm: 'RSA-OAEP'
      VolumeType: 'All'
    }
  }
}

// Install WSS Agent
resource vm_wssagentexe 'Microsoft.Compute/virtualMachines/runCommands@2022-11-01' = if (p_installWSS) {
  name: 'WSSAgentExe'
  location: p_hostPoolConfig.location
  tags: p_tags
  parent: virtualMachine
  properties: {
    source: {
      script: p_WSScmd
    }
    timeoutInSeconds: 600
    asyncExecution: false
  }
}

// Hybrid join
module mod_vdi_hybrid_ad_join '../shared/vdi_hybrid_ad_join.bicep' = if (p_hybridJoin) {
  name: 'mod-vdi-hybrid-ad-join-${p_vmName}-${p_deployTime}'
  params: {
    p_location: p_hostPoolConfig.location
    p_tags: p_tags
    p_ADDomain: p_envVars.haadjDomainToJoin
    p_ouPath: '${p_envNames.haadjOUPath},${p_envVars.haadjDomainDN}'
    p_vmName: virtualMachine.name
    p_adJoinUser: '${p_envVars.haadjDomainToJoin}\\${p_envVars.haadjJoinUsername}'
    p_adJoinPassword: avdKV.getSecret(p_envVars.haadjSecretName)
  }
  dependsOn: [
    vm_wssagentexe
  ]
}

// Start AAD join task
resource aad_register 'Microsoft.Compute/virtualMachines/runCommands@2022-11-01' = if (p_hybridJoin) {
  name: 'StartAADRegistrationTask'
  location: p_hostPoolConfig.location
  tags: p_tags
  parent: virtualMachine
  properties: {
    source: {
      script: 'powershell.exe -Command "gpupdate /force;Start-ScheduledTask -TaskPath \'\\Microsoft\\Windows\\Workplace Join\\\' -TaskName \'Automatic-Device-Join\'"'
    }
    timeoutInSeconds: 300
    asyncExecution: false
  }
  dependsOn: [
    mod_vdi_hybrid_ad_join
  ]
}

// Install AMA
resource ama_install 'Microsoft.Compute/virtualMachines/extensions@2022-03-01' = {
  name: 'AzureMonitorWindowsAgent'
  location: p_hostPoolConfig.location
  tags: p_tags
  parent: virtualMachine
  properties: {
    publisher: 'Microsoft.Azure.Monitor'
    type: 'AzureMonitorWindowsAgent'
    typeHandlerVersion: '1.0'
    autoUpgradeMinorVersion: true
    enableAutomaticUpgrade: true
  }
  dependsOn: [
    vm_wssagentexe
  ]
}

// Associate primary DCR
resource dcr_association 'Microsoft.Insights/dataCollectionRuleAssociations@2021-04-01' = {
  name: p_dcrRuleName
  scope: virtualMachine
  properties: {
    description: 'Association of data collection rule. Deleting this association will break the data collection for this virtual machine.'
    dataCollectionRuleId: p_dcrRuleId
  }
  dependsOn: [
    ama_install
  ]
}

// Register with host pool
module mod_vdi_hostpool_registration 'vdi_hostpool_registration.bicep' = if (p_hostPoolRegistration && !p_hostPoolRegistered) {
  name: 'mod-vdi-hostpool-registration-${p_vmName}-${p_deployTime}'
  params: {
    p_location: p_hostPoolConfig.location
    p_hostPoolName: p_hostPoolName
    p_avdAgentLocation: p_globalVars.avdAgentLocation
    p_hplToken: p_hplToken
    p_tags: p_tags
    p_vmName: p_vmName
  }
  dependsOn: [
    mod_vdi_hybrid_ad_join
    dcr_association
    ama_install
    aad_register
    vm_wssagentexe
  ]
}
