@description('Location for all resources.')
param location string

@description('Tags applied to all resources.')
param tags object

@description('Token used to build unique resource names.')
param resourceToken string

@description('Developer object id for data-plane roles. Empty skips them.')
param principalId string = ''

var functionAppName = 'func-orderflow-${resourceToken}'
var deploymentContainerName = 'app-package-${resourceToken}'

// Built-in role definition ids
var roles = {
  storageBlobDataOwner: 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
  storageBlobDataContributor: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
  storageQueueDataContributor: '974c5e8b-45b9-4653-ba55-5f855dd0fb88'
  storageTableDataContributor: '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3'
  serviceBusDataOwner: '090c5cfd-751d-490a-894a-3ce6f1109419'
  eventHubsDataOwner: 'f526a384-b230-433a-b45c-95f59c4a2dec'
}

// ---------------------------------------------------------------------------
// Host storage: Functions runtime state, deployment package, Event Hubs checkpoints
// ---------------------------------------------------------------------------
resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: 'st${resourceToken}'
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
  }

  resource blobService 'blobServices' = {
    name: 'default'
    resource deploymentContainer 'containers' = {
      name: deploymentContainerName
    }
  }
}

// ---------------------------------------------------------------------------
// Work storage: product images (Event Grid source) + the Storage queue
// ---------------------------------------------------------------------------
resource workStorage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: 'stwork${resourceToken}'
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
  }

  resource blobService 'blobServices' = {
    name: 'default'
    resource images 'containers' = {
      name: 'product-images'
    }
    resource thumbnails 'containers' = {
      name: 'thumbnails'
    }
    resource deadLetter 'containers' = {
      name: 'eventgrid-deadletter'
    }
  }

  resource queueService 'queueServices' = {
    name: 'default'
    resource imageJobs 'queues' = {
      name: 'image-jobs'
    }
    // Storage queues have no dead-letter queue. The Functions host moves messages here
    // after maxDequeueCount; pre-created so it is visible before the first failure.
    resource imageJobsPoison 'queues' = {
      name: 'image-jobs-poison'
    }
  }
}

// ---------------------------------------------------------------------------
// Service Bus: topic for OrderPlaced (fan-out), queue for ShipOrder (one owner)
// Standard tier: Basic has no topics, sessions, transactions or duplicate detection.
// ---------------------------------------------------------------------------
resource serviceBus 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: 'sb-${resourceToken}'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }
  properties: {
    disableLocalAuth: true
    minimumTlsVersion: '1.2'
  }

  resource ordersTopic 'topics' = {
    name: 'orders'
    properties: {
      requiresDuplicateDetection: true
      duplicateDetectionHistoryTimeWindow: 'PT10M'
      defaultMessageTimeToLive: 'P1D'
    }

    resource payment 'subscriptions' = {
      name: 'payment'
      properties: {
        maxDeliveryCount: 3
        lockDuration: 'PT1M'
        deadLetteringOnMessageExpiration: true
      }
    }

    resource inventory 'subscriptions' = {
      name: 'inventory'
      properties: {
        maxDeliveryCount: 5
        deadLetteringOnMessageExpiration: true
      }
    }

    resource notification 'subscriptions' = {
      name: 'notification'
      properties: {
        maxDeliveryCount: 5
        deadLetteringOnMessageExpiration: true
      }
    }

    resource fraudReview 'subscriptions' = {
      name: 'fraud-review'
      properties: {
        maxDeliveryCount: 5
        deadLetteringOnMessageExpiration: true
      }

      // This subscription should only see high-value orders. Rules evaluate application
      // properties set by the publisher, not the JSON body.
      // Service Bus also gives every new subscription a '$Default' TrueFilter rule, and
      // rules are OR-ed, so that default would let every order through. Redeclaring
      // '$Default' here could not be confirmed to replace it, so the rule gets its own name
      // and scripts/postdeploy.ps1 deletes any other rule on this subscription.
      resource highValue 'rules' = {
        name: 'high-value'
        properties: {
          filterType: 'SqlFilter'
          sqlFilter: {
            sqlExpression: 'total >= 1000'
          }
        }
      }
    }
  }

  resource shipmentsQueue 'queues' = {
    name: 'shipments'
    properties: {
      requiresSession: true
      requiresDuplicateDetection: true
      duplicateDetectionHistoryTimeWindow: 'PT10M'
      maxDeliveryCount: 5
      deadLetteringOnMessageExpiration: true
      defaultMessageTimeToLive: 'P1D'
    }
  }
}

// ---------------------------------------------------------------------------
// Event Hubs: vehicle telemetry stream, two independent consumer groups.
// Standard tier: Basic allows only the $Default consumer group.
// ---------------------------------------------------------------------------
resource eventHubs 'Microsoft.EventHub/namespaces@2024-01-01' = {
  name: 'evhns-${resourceToken}'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Standard'
    capacity: 1
  }
  properties: {
    disableLocalAuth: true
    minimumTlsVersion: '1.2'
  }

  resource telemetry 'eventhubs' = {
    name: 'telemetry'
    properties: {
      partitionCount: 4
      messageRetentionInDays: 1
    }

    resource aggregator 'consumergroups' = {
      name: 'aggregator'
    }

    resource alerts 'consumergroups' = {
      name: 'alerts'
    }
  }
}

// ---------------------------------------------------------------------------
// Event Grid: system topic on the work storage account. The event subscription
// that pushes BlobCreated to the function is created after deploy
// (scripts/postdeploy.ps1 + eventgrid-subscription.bicep) because the function
// and its Event Grid webhook key don't exist until the code is deployed.
// ---------------------------------------------------------------------------
resource eventGridTopic 'Microsoft.EventGrid/systemTopics@2022-06-15' = {
  name: 'evgt-${resourceToken}'
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    source: workStorage.id
    topicType: 'Microsoft.Storage.StorageAccounts'
  }
}

// ---------------------------------------------------------------------------
// Monitoring
// ---------------------------------------------------------------------------
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'log-${resourceToken}'
  location: location
  tags: tags
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-${resourceToken}'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
}

// ---------------------------------------------------------------------------
// Function app on Flex Consumption, managed identity everywhere, no keys
// ---------------------------------------------------------------------------
resource plan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: 'plan-${resourceToken}'
  location: location
  tags: tags
  kind: 'functionapp'
  sku: {
    name: 'FC1'
    tier: 'FlexConsumption'
  }
  properties: {
    reserved: true
  }
}

resource functionApp 'Microsoft.Web/sites@2024-04-01' = {
  name: functionAppName
  location: location
  tags: union(tags, { 'azd-service-name': 'orderflow' })
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${storage.properties.primaryEndpoints.blob}${deploymentContainerName}'
          authentication: {
            type: 'SystemAssignedIdentity'
          }
        }
      }
      scaleAndConcurrency: {
        maximumInstanceCount: 40
        instanceMemoryMB: 2048
      }
      runtime: {
        name: 'dotnet-isolated'
        version: '8.0'
      }
    }
    siteConfig: {
      minTlsVersion: '1.2'
      appSettings: [
        {
          name: 'AzureWebJobsStorage__accountName'
          value: storage.name
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
        {
          name: 'ServiceBus__fullyQualifiedNamespace'
          value: '${serviceBus.name}.servicebus.windows.net'
        }
        {
          name: 'EventHubs__fullyQualifiedNamespace'
          value: '${eventHubs.name}.servicebus.windows.net'
        }
        {
          name: 'WorkStorage__blobServiceUri'
          value: workStorage.properties.primaryEndpoints.blob
        }
        {
          name: 'WorkStorage__queueServiceUri'
          value: workStorage.properties.primaryEndpoints.queue
        }
      ]
    }
  }
}

// ---------------------------------------------------------------------------
// Role assignments: function app identity
// ---------------------------------------------------------------------------
var hostStorageRoles = [
  roles.storageBlobDataOwner
  roles.storageQueueDataContributor
  roles.storageTableDataContributor
]

resource hostStorageRoleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for roleId in hostStorageRoles: {
    name: guid(storage.id, functionApp.id, roleId)
    scope: storage
    properties: {
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleId)
      principalId: functionApp.identity.principalId
      principalType: 'ServicePrincipal'
    }
  }
]

var workStorageRoles = [
  roles.storageBlobDataContributor
  roles.storageQueueDataContributor
]

resource workStorageRoleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for roleId in workStorageRoles: {
    name: guid(workStorage.id, functionApp.id, roleId)
    scope: workStorage
    properties: {
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleId)
      principalId: functionApp.identity.principalId
      principalType: 'ServicePrincipal'
    }
  }
]

resource serviceBusRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(serviceBus.id, functionApp.id, roles.serviceBusDataOwner)
  scope: serviceBus
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.serviceBusDataOwner)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource eventHubsRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(eventHubs.id, functionApp.id, roles.eventHubsDataOwner)
  scope: eventHubs
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.eventHubsDataOwner)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Event Grid system topic identity writes undeliverable events to the dead-letter container
// (shared key access is disabled on the account, so identity is the only way in).
resource eventGridDeadLetterRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(workStorage.id, eventGridTopic.id, roles.storageBlobDataContributor)
  scope: workStorage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.storageBlobDataContributor)
    principalId: eventGridTopic.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ---------------------------------------------------------------------------
// Role assignments: developer (demo script uploads blobs; local func host)
// ---------------------------------------------------------------------------
resource devWorkStorageRoleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for roleId in workStorageRoles: if (!empty(principalId)) {
    name: guid(workStorage.id, principalId, roleId)
    scope: workStorage
    properties: {
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleId)
      principalId: principalId
      principalType: 'User'
    }
  }
]

resource devServiceBusRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(principalId)) {
  name: guid(serviceBus.id, principalId, roles.serviceBusDataOwner)
  scope: serviceBus
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.serviceBusDataOwner)
    principalId: principalId
    principalType: 'User'
  }
}

resource devEventHubsRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(principalId)) {
  name: guid(eventHubs.id, principalId, roles.eventHubsDataOwner)
  scope: eventHubs
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.eventHubsDataOwner)
    principalId: principalId
    principalType: 'User'
  }
}

output functionAppName string = functionApp.name
output functionAppUri string = 'https://${functionApp.properties.defaultHostName}'
output serviceBusNamespace string = serviceBus.name
output eventHubsNamespace string = eventHubs.name
output workStorageName string = workStorage.name
output eventGridSystemTopicName string = eventGridTopic.name
