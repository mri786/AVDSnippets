targetScope = 'resourceGroup'

//***** PARAMETERS *****//

@description('Environment short name')
param p_envNames object

@description('Host pool configuration object')
param p_hostPoolConfig object

@description('Whether to use validation enviroment.')
param p_validationEnvironment bool = false

@description('Whether to use validation enviroment.')
param p_startVMOnConnect bool = false

@description('Hostpool RDP properties')
param p_customRdpProperty string

@description('Current time in UTC')
param p_utctime string = utcNow()

@description('How long the registration token should be valid for')
param p_tokenExpirationHours int = 175

@description('Azure tags to add to resources')
param p_tags object


//***** RESOURCES *****//

resource hostpoolName_resource 'Microsoft.DesktopVirtualization/hostPools@2022-04-01-preview' = {
  name: p_envNames.hostPoolName
  location: p_hostPoolConfig.location
  tags: p_tags
  properties: {
    friendlyName: p_envNames.hostPoolFriendlyName
    description: p_envNames.hostPoolDescription
    hostPoolType: 'Pooled'
    maxSessionLimit: p_hostPoolConfig.hostPool.maxSessionLimit
    loadBalancerType: 'BreadthFirst'
    validationEnvironment: ((p_validationEnvironment == 'True') ? bool('true') : bool('false'))
    startVMOnConnect: p_startVMOnConnect
    preferredAppGroupType: p_hostPoolConfig.hostpool.prefferedAppGroupType
    customRdpProperty: p_customRdpProperty
    registrationInfo: {
      expirationTime: dateTimeAdd(p_utctime, 'PT${p_tokenExpirationHours}H10M')
      token: null
      registrationTokenOperation: 'Update'
    }
    agentUpdate: {
      type: p_hostPoolConfig.hostpool.agentUpdate.type
      maintenanceWindowTimeZone: p_hostPoolConfig.hostpool.agentUpdate.maintenanceWindowTimeZone
      useSessionHostLocalTime: p_hostPoolConfig.hostpool.agentUpdate.useSessionHostLocalTime
      maintenanceWindows: [
        {
          dayOfWeek: p_hostPoolConfig.hostpool.agentUpdate.maintenanceWindows.dayOfWeek
          hour: p_hostPoolConfig.hostpool.agentUpdate.maintenanceWindows.hour
        }
      ]
    }    
  }
  
}


