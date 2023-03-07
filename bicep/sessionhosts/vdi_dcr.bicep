//***** PARAMETERS *****//

@description('Environment short name')
param p_dcrRuleName string

@description('Azure location')
param p_location string

@description('Log Analytics Workspace resource Id')
param p_LAWResourceId string

@description('Azure tags to add to resources')
param p_tags object

//***** RESOURCES *****//

resource ama_dcr 'Microsoft.Insights/dataCollectionRules@2021-04-01' = {
  name: p_dcrRuleName
  location: p_location
  tags: p_tags
  kind: 'Windows'
  properties: {
    description: '${p_dcrRuleName} Data Collection Rule'
    dataFlows: [
      {
        streams: [
          'Microsoft-Perf'
          'Microsoft-Event'
        ]
        destinations: [
            'LADestination'
        ]
      }
    ]
    dataSources: {
      performanceCounters: [
        {
          name: 'perfCountersSource'
          samplingFrequencyInSeconds: 60
          streams: [
            'Microsoft-Perf'
          ]
          counterSpecifiers: [
            '\\LogicalDisk(C:)\\% Free Space'
            '\\LogicalDisk(C:)\\Avg. Disk Queue Length'
            '\\LogicalDisk(C:)\\Avg. Disk sec/Transfer'
            '\\LogicalDisk(C:)\\Current Disk Queue Length'
            '\\Memory\\Available Mbytes'
            '\\Memory\\Page Faults/sec'
            '\\Memory\\Pages/sec'
            '\\Memory\\% Committed Bytes In Use'
            '\\PhysicalDisk(*)\\Avg. Disk Queue Length'
            '\\PhysicalDisk(*)\\Avg. Disk sec/Read'
            '\\PhysicalDisk(*)\\Avg. Disk sec/Transfer'
            '\\PhysicalDisk(*)\\Avg. Disk sec/Write'
            '\\Processor Information(_Total)\\% Processor Time'
            '\\Process(*)\\% Processor Time'
            '\\Process(*)\\Working Set'
            '\\Terminal Services\\Active Sessions'
            '\\Terminal Services\\Inactive Sessions'
            '\\Terminal Services\\Total Sessions'
            '\\Terminal Services Session(*)\\% Processor Time'
            '\\Terminal Services Session(*)\\Working Set'
            '\\Terminal Services Session(*)\\Working Set Peak'
            '\\User Input Delay per Process(*)\\Max Input Delay'
            '\\User Input Delay per Session(*)\\Max Input Delay'
            '\\RemoteFX Network(*)\\Current TCP RTT'
            '\\RemoteFX Network(*)\\Current UDP Bandwidth'
          ]
        }
      ]
      windowsEventLogs: [
        {
          name: 'eventLogsSource'
          streams: [
            'Microsoft-Event'
          ]
          xPathQueries: [
            'Application!*[System[(Level=1 or Level=2 or Level=3)]]'
            'System!*[System[(Level=1 or Level=2 or Level=3)]]'
            'Security!*[System[(band(Keywords,13510798882111488)) and (EventID != 5152 and EventID != 5157 and EventID != 5447)]]'
            'Microsoft-Windows-TerminalServices-LocalSessionManager/Operational!*[System[(Level=1  or Level=2 or Level=3 or Level=4 or Level=0)]]'
            'Microsoft-Windows-TerminalServices-RemoteConnectionManager/Admin!*[System[(Level=1  or Level=2 or Level=3 or Level=4 or Level=0)]]'
            'Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational!*[System[(Level=1  or Level=2 or Level=3 or Level=4 or Level=0)]]'
            'Microsoft-FSLogix-Apps/Operational!*[System[(Level=1  or Level=2 or Level=3 or Level=4 or Level=0)]]'
            'Microsoft-FSLogix-Apps/Admin!*[System[(Level=1  or Level=2 or Level=3 or Level=4 or Level=0)]]'
          ]
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          name: 'LADestination'
          workspaceResourceId: p_LAWResourceId
        }
      ]
    }
  }
}

//***** OUTPUTS *****//

output o_dcrRuleName string = ama_dcr.name
output o_dcrRuleId string = ama_dcr.id
