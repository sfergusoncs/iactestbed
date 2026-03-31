param location string = resourceGroup().location
param addressPrefixes array
param subnets array
param enableDdosProtection bool = false
param environment string

var tags = {
  app: 'sandman'
  env: environment
}

resource vnet 'Microsoft.Network/virtualNetworks@2021-05-01' = {
  name: 'sandman-vnet-${environment}'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: addressPrefixes
    }
    enableDdosProtection: enableDdosProtection
    subnets: [
      for s in subnets: {
        name: s.name
        properties: {
          addressPrefix: s.properties.addressPrefix
          delegations: s.properties.delegations
          privateEndpointNetworkPolicies: s.properties.privateEndpointNetworkPolicies
          privateLinkServiceNetworkPolicies: s.properties.privateLinkServiceNetworkPolicies
        }
      }
    ]
  }
}

output vnetId string = vnet.id
output vnetName string = vnet.name
output aksSubnetId string = vnet.properties.subnets[0].id
output peSubnetId string = vnet.properties.subnets[1].id
