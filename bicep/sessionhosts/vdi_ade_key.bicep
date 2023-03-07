//***** PARAMETERS *****//

@description('Whether to create a new key or retrieve the existing one')
param p_newKey bool

@description('Name of Key vault to use')
param p_kvName string

@description('Key name to create or retrieve')
param p_keyName string

@description('Azure tags to add to resources')
param p_tags object

@description('Deployment time, must be utcnow() and should not be supplied at runtime')
param p_deployTime string = utcNow()

//***** VARIABLES *****//

var v_exp = dateTimeToEpoch(dateTimeAdd(p_deployTime, 'P1Y'))

//***** RESOURCES *****//

resource kv 'Microsoft.KeyVault/vaults@2021-10-01' existing = {
  name: p_kvName
}

// Only create new key if one doesn't exist to avoid unsupported expiry change
resource newKey 'Microsoft.KeyVault/vaults/keys@2022-07-01' = if(p_newKey) {
  name: p_keyName
  tags: p_tags
  parent: kv
  properties: {
    attributes: {
      enabled: true
      exp: v_exp
      // exp: 1706963426
    }
    curveName: 'P-256K'
    keyOps: [
      'encrypt'
      'decrypt'
      'wrapKey'
      'unwrapKey'
    ]
    keySize: 3072
    kty: 'RSA'
  }
}

// Get key details whether regardless of whether it is new or existing
resource existingKey 'Microsoft.KeyVault/vaults/keys@2021-10-01' existing = if(!p_newKey) {
  name: p_keyName
  parent: kv
}

//***** OUTPUTS *****//

output kekUrl string = p_newKey ? newKey.properties.keyUriWithVersion : existingKey.properties.keyUriWithVersion
output kvUrl string = kv.properties.vaultUri
output kvId string = kv.id
