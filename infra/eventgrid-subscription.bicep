// Deployed by scripts/postdeploy.ps1 AFTER `azd deploy`, because the webhook
// needs the function to exist and the host's eventgrid_extension system key.

@description('Name of the Flex Consumption function app.')
param functionAppName string

@description('Name of the Event Grid system topic on the work storage account.')
param systemTopicName string

@description('Name of the work storage account (dead-letter destination).')
param workStorageName string

@secure()
@description('The function host eventgrid_extension system key.')
param eventGridExtensionKey string

resource functionApp 'Microsoft.Web/sites@2024-04-01' existing = {
  name: functionAppName
}

resource workStorage 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: workStorageName
}

resource systemTopic 'Microsoft.EventGrid/systemTopics@2022-06-15' existing = {
  name: systemTopicName
}

resource imageUploaded 'Microsoft.EventGrid/systemTopics/eventSubscriptions@2022-06-15' = {
  parent: systemTopic
  name: 'image-uploaded'
  properties: {
    destination: {
      endpointType: 'WebHook'
      properties: {
        endpointUrl: 'https://${functionApp.properties.defaultHostName}/runtime/webhooks/eventgrid?functionName=OnImageUploaded&code=${eventGridExtensionKey}'
        maxEventsPerBatch: 1
        preferredBatchSizeInKilobytes: 64
      }
    }
    filter: {
      includedEventTypes: [
        'Microsoft.Storage.BlobCreated'
      ]
      subjectBeginsWith: '/blobServices/default/containers/product-images/'
    }
    eventDeliverySchema: 'EventGridSchema'
    // These are the defaults, spelled out so the post can point at them.
    retryPolicy: {
      maxDeliveryAttempts: 30
      eventTimeToLiveInMinutes: 1440
    }
    // Off by default in Event Grid. Without it, an event that exhausts its retries is dropped.
    deadLetterWithResourceIdentity: {
      identity: {
        type: 'SystemAssigned'
      }
      deadLetterDestination: {
        endpointType: 'StorageBlob'
        properties: {
          resourceId: workStorage.id
          blobContainerName: 'eventgrid-deadletter'
        }
      }
    }
  }
}

output eventSubscriptionName string = imageUploaded.name
