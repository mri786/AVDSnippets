//***** PARAMETERS *****//

@description('Environment deployment variables')
param p_envVars object

@description('Environment names')
param p_envNames object

@description('Host pool configuration object')
param p_hostPoolConfig object

@description('Hashtable of VmName:SecureString')
@secure()
param p_localAdminPassword string

@description('VM Name')
param p_TempVmName string

@description('VM Size')
param p_VMSize string = 'Standard_B2ms'

@description('VM Disk Type')
param p_VMDiskType string = 'StandardSSD_LRS'

@description('WSS Agent installation command')
param p_WSScmd string

@description('Azure tags to add to resources')
param p_tags object

param p_identityId string

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

// Create network interfaces
resource nic 'Microsoft.Network/networkInterfaces@2022-01-01' = {
  name: '${p_TempVmName}-nic'
  location: p_hostPoolConfig.location
  tags: p_tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig'
        properties: {
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

// Create Temp VM
resource virtualMachine 'Microsoft.Compute/virtualMachines@2022-03-01' = {
  name: p_TempVmName
  location: p_hostPoolConfig.location
  tags: p_tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities:{
      '${p_identityId}': {}
    }
  }
  properties: {
    licenseType: 'Windows_Client'
    hardwareProfile: {
      vmSize: p_VMSize
    }
    osProfile: {
      computerName: p_TempVmName
      adminUsername: p_hostPoolConfig.sessionHosts.localAdminUsername
      adminPassword: p_localAdminPassword
      windowsConfiguration: {
        enableAutomaticUpdates: false
        patchSettings: {
          patchMode: 'Manual'
        }
        provisionVMAgent: true
      }
      allowExtensionOperations: true
    }
    storageProfile: {
      osDisk: {
        name: '${p_TempVmName}-osdisk'
        managedDisk: {
          storageAccountType: p_VMDiskType
        }
        diskSizeGB: 128
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
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }

}

// Install WSS Agent
resource vm_wssagentexe 'Microsoft.Compute/virtualMachines/runCommands@2022-11-01' = {
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

// Hybrid join temp VM
module mod_vdi_hybrid_ad_join '../shared/vdi_hybrid_ad_join.bicep' = {
  name: 'mod-vdi-hybrid-ad-join-${p_TempVmName}-${p_deployTime}'
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
