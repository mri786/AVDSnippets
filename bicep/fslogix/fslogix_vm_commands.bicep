param p_location string
param p_TempVmName string
param p_setNTFSCmd string
param p_setRedirCmd string

@description('Azure tags to add to resources')
param p_tags object

// Get the temporary VM resource
resource virtualMachine 'Microsoft.Compute/virtualMachines@2022-03-01' existing = {
  name: p_TempVmName
}

resource setRedirectionXml 'Microsoft.Compute/virtualMachines/runCommands@2022-03-01' = {
  name: 'setRedirectionXml'
  parent: virtualMachine
  location: p_location
  properties: {
    source: {
      script: p_setRedirCmd
    }
    asyncExecution: false
    timeoutInSeconds: 600
  }
  tags: p_tags
}

resource setNTFSPermissions 'Microsoft.Compute/virtualMachines/runCommands@2022-03-01' = {
  name: 'setNTFSPermissions'
  parent: virtualMachine
  location: p_location
  properties: {
    source: {
      script: p_setNTFSCmd
    }
    asyncExecution: false
    timeoutInSeconds: 600
  }
  tags: p_tags
  dependsOn:[
    setRedirectionXml
  ]
}
