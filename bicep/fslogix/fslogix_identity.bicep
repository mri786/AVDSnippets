
param p_TempVmName string
param p_location string
param p_tags object

resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: '${p_TempVmName}-fslogix-msi'
  location: p_location
  tags: p_tags
}

output o_uaiId string = userAssignedIdentity.id
output o_uaiPrincipalId string = userAssignedIdentity.properties.principalId
