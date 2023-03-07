//***** PARAMETERS *****//

@description('Application Security Group Name to associate with VM network interface')
param p_asgName string

@description('Azure tags to add to resources')
param p_tags object

@description('Azure location')
param p_location string

//***** RESOURCES *****//

resource asg 'Microsoft.Network/applicationSecurityGroups@2022-07-01' = {
  name: p_asgName
  location: p_location
  tags: p_tags
}

//***** OUTPUTS *****//

output asgId string = asg.id
