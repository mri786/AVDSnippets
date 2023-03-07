targetScope = 'resourceGroup'

//***** PARAMETERS *****//

@description('Profile Share Name')
param p_profileShareName string

@description('Profile Share Name')
param p_redirShareName string

@description('FSLogix storage account name')
param p_fslogixStorageAccount string


//***** RESOURCES *****//

resource fslogixStorageAccount 'Microsoft.Storage/storageAccounts@2021-09-01' existing = {
  name: p_fslogixStorageAccount
}

resource fslogixStorageAccount_fileservices 'Microsoft.Storage/storageAccounts/fileservices@2021-09-01' existing = {
  parent: fslogixStorageAccount
  name: 'default'
}

resource profileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2022-09-01' = {
  name: p_profileShareName
  parent: fslogixStorageAccount_fileservices
  properties: {
        enabledProtocols: 'SMB'
        shareQuota: 5120
  }
}

resource redirectionShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2022-09-01' = {
  name: p_redirShareName
  parent: fslogixStorageAccount_fileservices
  properties: {
        enabledProtocols: 'SMB'
        shareQuota: 5120
  }
}
