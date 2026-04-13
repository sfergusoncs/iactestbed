param location string = resourceGroup().location
param routeTableName string
param routes array = []
param tags object = {}

resource routeTable 'Microsoft.Network/routeTables@2023-04-01' = {
  name: routeTableName
  location: location
  tags: tags
  properties: {
    disableBgpRoutePropagation: false
    routes: [
      for route in routes: {
        name: route.name
        properties: {
          addressPrefix: route.addressPrefix
          nextHopType: route.nextHopType
          nextHopIpAddress: route.nextHopIpAddress
        }
      }
    ]
  }
}

output routeTableId string = routeTable.id
