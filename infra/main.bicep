targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the azd environment, used to derive resource names.')
param environmentName string

// No default on purpose: at subscription scope azd needs AZURE_LOCATION in the env to know
// where to put the deployment itself. A Bicep default hides azd's location prompt, and the
// deployment then fails with "The 'location' property must be specified".
@minLength(1)
@description('Primary location for all resources. Comes from AZURE_LOCATION.')
param location string

@description('Object id of the developer running azd. Gets data-plane roles so the demo script and a local func host work with az login. Leave empty to skip.')
param principalId string = ''

var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var tags = { 'azd-env-name': environmentName }

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-${environmentName}'
  location: location
  tags: tags
}

module resources 'resources.bicep' = {
  name: 'resources'
  scope: rg
  params: {
    location: location
    tags: tags
    resourceToken: resourceToken
    principalId: principalId
  }
}

output AZURE_LOCATION string = location
output AZURE_RESOURCE_GROUP string = rg.name
output AZURE_FUNCTION_APP_NAME string = resources.outputs.functionAppName
output FUNCTION_BASE_URL string = '${resources.outputs.functionAppUri}/api'
output SERVICEBUS_NAMESPACE string = resources.outputs.serviceBusNamespace
output EVENTHUBS_NAMESPACE string = resources.outputs.eventHubsNamespace
output WORK_STORAGE_ACCOUNT_NAME string = resources.outputs.workStorageName
output EVENTGRID_SYSTEM_TOPIC_NAME string = resources.outputs.eventGridSystemTopicName
