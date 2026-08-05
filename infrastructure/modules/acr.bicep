// ACR itself lives only in the hub subscription now. This module runs against
// sandman-rg-hub (under the hub service connection) and just links the spoke's
// VNet to the hub's existing privatelink.azurecr.io private DNS zone, so pods in
// the spoke cluster can resolve the hub ACR's private endpoint.
param environment string
param vnetId string

var tags = {
  app: 'sandman'
  env: environment
}

resource acrPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  name: 'privatelink.azurecr.io'
}

resource acrPrivateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: acrPrivateDnsZone
  name: 'sandman-dns-link-acr-${environment}'
  location: 'global'
  tags: tags
  properties: {
    virtualNetwork: {
      id: vnetId
    }
    registrationEnabled: false
  }
}
