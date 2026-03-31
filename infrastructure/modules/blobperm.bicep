param environment string
param location string = resourceGroup().location
param subnetId string
param vnetId string
param skuName string = 'Standard_LRS'
param shareQuotaGB int = 100
param shareName string = 'sandmanfiles-${environment}'
param deleteRetentionDays int
param enableBackup bool = false

var storageAccountName = 'sandmanperm${environment}'
var rsvResourceGroup = 'sandman-rg-rsv-${environment}'
var rsvName = 'sandman-rsv-${environment}'

var tags = {
  app: 'sandman'
  env: environment
}

// Storage Account
resource storageAccount 'Microsoft.Storage/storageAccounts@2025-06-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: skuName
  }
  kind: 'StorageV2'
  properties: {
    publicNetworkAccess: 'Disabled'
    allowBlobPublicAccess: false
    allowCrossTenantReplication: false
    allowSharedKeyAccess: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    defaultToOAuthAuthentication: false
    dnsEndpointType: 'Standard'
    accessTier: 'Hot'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
      ipRules: []
      virtualNetworkRules: []
      resourceAccessRules: []
    }
    encryption: {
      keySource: 'Microsoft.Storage'
      requireInfrastructureEncryption: false
      services: {
        blob: {
          keyType: 'Account'
          enabled: true
        }
        file: {
          keyType: 'Account'
          enabled: true
        }
      }
    }
  }
}

// File Service
resource fileService 'Microsoft.Storage/storageAccounts/fileServices@2025-06-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    shareDeleteRetentionPolicy: {
      enabled: true
      days: deleteRetentionDays
    }
    cors: {
      corsRules: []
    }
    protocolSettings: {
      smb: {}
    }
  }
}

// File Share
resource fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2025-06-01' = {
  parent: fileService
  name: shareName
  properties: {
    shareQuota: shareQuotaGB
    enabledProtocols: 'SMB'
  }
}

// Private Endpoint
resource filesPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-04-01' = {
  name: 'sandman-pe-blobperm-${environment}'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: subnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'sandman-pe-blobperm-${environment}'
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: [
            'file'
          ]
        }
      }
    ]
  }
}

// Private DNS Zone
resource filesDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  #disable-next-line no-hardcoded-env-urls
  name: 'privatelink.file.core.windows.net'
  location: 'global'
  tags: tags
}

// VNet Link
resource filesDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: filesDnsZone
  name: 'sandman-dns-link-blobperm-${environment}'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnetId
    }
    registrationEnabled: false
  }
}

// DNS Zone Group
resource filesPrivateEndpointDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-04-01' = {
  parent: filesPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-file-core-windows-net'
        properties: {
          privateDnsZoneId: filesDnsZone.id
        }
      }
    ]
  }
}

// Recovery Services Vault — deployed into its own RG, RG created by pipeline
module rsvModule 'rsv.bicep' = if (enableBackup) {
  name: 'deploy-rsv'
  scope: resourceGroup(rsvResourceGroup)
  params: {
    location: location
    tags: tags
    rsvName: rsvName
    }
}

output storageAccountId string = storageAccount.id
output storageAccountName string = storageAccount.name
output fileShareName string = fileShare.name
