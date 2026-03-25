param vnetName string
param location string = resourceGroup().location
param addressPrefixes array
param subnets array
param enableDdosProtection bool = false
param tags object = {}

resource vnet 'Microsoft.Network/virtualNetworks@2021-05-01' = {
  name: vnetName
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
