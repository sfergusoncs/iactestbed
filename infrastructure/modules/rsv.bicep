param location string
param tags object
param rsvName string


// Recovery Services Vault
resource recoveryVault 'Microsoft.RecoveryServices/vaults@2024-04-01' = {
  name: rsvName
  location: location
  tags: tags
  sku: {
    name: 'RS0'
    tier: 'Standard'
  }
  properties: {
    publicNetworkAccess: 'Disabled'
  }
}

// Backup Policy
resource backupPolicy 'Microsoft.RecoveryServices/vaults/backupPolicies@2024-04-01' = {
  parent: recoveryVault
  name: 'sandman-backup-policy-files'
  properties: {
    backupManagementType: 'AzureStorage'
    workLoadType: 'AzureFileShare'
    schedulePolicy: {
      schedulePolicyType: 'SimpleSchedulePolicy'
      scheduleRunFrequency: 'Daily'
      scheduleRunTimes: [
        '2025-01-01T08:00:00Z'
      ]
    }
    retentionPolicy: {
      retentionPolicyType: 'LongTermRetentionPolicy'
      dailySchedule: {
        retentionTimes: [
          '2025-01-01T08:00:00Z'
        ]
        retentionDuration: {
          count: 30
          durationType: 'Days'
        }
      }
    }
    timeZone: 'Central Standard Time'
  }
}

output rsvId string = recoveryVault.id
output backupPolicyId string = backupPolicy.id
