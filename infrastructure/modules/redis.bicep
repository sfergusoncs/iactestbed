param environment string
param location string = resourceGroup().location
param subnetId string
param vnetId string
param skuName string = 'Balanced_B5'
param workloadIdentityObjectId string = ''



var redisName = 'sandman-redis-${environment}'

var tags = {
  app: 'sandman'
  env: environment
}

// Redis Enterprise Cluster
resource redisEnterprise 'Microsoft.Cache/redisEnterprise@2025-08-01-preview' = {
  name: redisName
  location: location
  tags: tags
  sku: {
    name: skuName
  }
    identity: {
    type: 'None'
  }
  properties: {
    minimumTlsVersion: '1.2'
    highAvailability: 'Enabled'
    publicNetworkAccess: 'Disabled'
  }
}

// Redis Database
resource redisDatabase 'Microsoft.Cache/redisEnterprise/databases@2025-08-01-preview' = {
  parent: redisEnterprise
  name: 'default'
  properties: {
    clientProtocol: 'Encrypted'
    port: 10000
    clusteringPolicy: 'EnterpriseCluster'
    evictionPolicy: 'NoEviction'
    modules: [
      {
        name: 'RedisJSON'
      }
      {
        name: 'RediSearch'
      }
    ]
    persistence: {
      aofEnabled: false
      rdbEnabled: false
    }
    deferUpgrade: 'NotDeferred'
    accessKeysAuthentication: 'Disabled'
  }
}

// Access Policy Assignment for Workload Identity
resource redisAccessPolicy 'Microsoft.Cache/redisEnterprise/databases/accessPolicyAssignments@2025-08-01-preview' = if (workloadIdentityObjectId != '') {
  parent: redisDatabase
  name: workloadIdentityObjectId
  properties: {
    accessPolicyName: 'default'
    user: {
      objectId: workloadIdentityObjectId
    }
  }
}

// Private Endpoint
resource redisPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-04-01' = {
  name: 'sandman-pe-redis-${environment}'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: subnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'sandman-pe-redis-${environment}'
        properties: {
          privateLinkServiceId: redisEnterprise.id
          groupIds: [
            'redisEnterprise'
          ]
        }
      }
    ]
  }
}

// Private DNS Zone
resource redisDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  #disable-next-line no-hardcoded-env-urls
  name: 'privatelink.redisenterprise.cache.azure.net'
  location: 'global'
  tags: tags
}

// VNet Link
resource redisDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: redisDnsZone
  name: 'sandman-dns-link-redis-${environment}'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnetId
    }
    registrationEnabled: false
  }
}

// DNS Zone Group
resource redisPrivateEndpointDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-04-01' = {
  parent: redisPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-redisenterprise-cache-azure-net'
        properties: {
          privateDnsZoneId: redisDnsZone.id
        }
      }
    ]
  }
}

output redisId string = redisEnterprise.id
output redisHostName string = redisEnterprise.properties.hostName
output redisDatabaseId string = redisDatabase.id
