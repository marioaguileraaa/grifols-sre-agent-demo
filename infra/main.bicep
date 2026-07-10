targetScope = 'subscription'

@description('Existing guarded resource group. The template never creates or deletes it.')
param resourceGroupName string = 'rg-demo-sre-agent-v1'

@description('Azure region for all regional resources.')
param location string = 'eastus2'

@description('Optional immutable backend image. The public placeholder is used before remote builds.')
param backendImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

@description('Optional immutable frontend image. The public placeholder is used before remote builds.')
param frontendImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

var monitoringContributorRoleId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '749f88d5-cbae-40b8-bcfc-e573ddc772fa'
)

resource resourceGroup 'Microsoft.Resources/resourceGroups@2024-11-01' existing = {
  name: resourceGroupName
}

module platform 'platform.bicep' = {
  name: 'grifols-plasma-supply-platform'
  scope: resourceGroup
  params: {
    location: location
    backendImage: backendImage
    frontendImage: frontendImage
  }
}

resource sreMonitoringContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, resourceGroup.id, 'id-grifols-sre-v1', monitoringContributorRoleId)
  properties: {
    roleDefinitionId: monitoringContributorRoleId
    principalId: platform.outputs.sreIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId
output AZURE_SUBSCRIPTION_ID string = subscription().subscriptionId
output AZURE_RESOURCE_GROUP string = resourceGroup.name
output RESOURCE_GROUP_ID string = resourceGroup.id
output LOG_ANALYTICS_WORKSPACE_ID string = platform.outputs.logAnalyticsWorkspaceId
output LOG_ANALYTICS_WORKSPACE_NAME string = platform.outputs.logAnalyticsWorkspaceName
output APPLICATION_INSIGHTS_ID string = platform.outputs.applicationInsightsId
output APPLICATION_INSIGHTS_APP_ID string = platform.outputs.applicationInsightsAppId
output AZURE_CONTAINER_REGISTRY_ID string = platform.outputs.containerRegistryId
output AZURE_CONTAINER_REGISTRY_NAME string = platform.outputs.containerRegistryName
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = platform.outputs.containerRegistryLoginServer
output CONTAINER_APPS_ENVIRONMENT_ID string = platform.outputs.containerAppsEnvironmentId
output CONTAINER_APPS_ENVIRONMENT_NAME string = platform.outputs.containerAppsEnvironmentName
output APP_PULL_IDENTITY_ID string = platform.outputs.appPullIdentityId
output BACKEND_CONTAINER_APP_ID string = platform.outputs.backendContainerAppId
output BACKEND_CONTAINER_APP_NAME string = platform.outputs.backendContainerAppName
output BACKEND_FQDN string = platform.outputs.backendFqdn
output API_BASE_URL string = 'https://${platform.outputs.backendFqdn}'
output FRONTEND_CONTAINER_APP_ID string = platform.outputs.frontendContainerAppId
output FRONTEND_CONTAINER_APP_NAME string = platform.outputs.frontendContainerAppName
output FRONTEND_FQDN string = platform.outputs.frontendFqdn
output FRONTEND_URL string = 'https://${platform.outputs.frontendFqdn}'
output SRE_IDENTITY_ID string = platform.outputs.sreIdentityId
output SRE_IDENTITY_PRINCIPAL_ID string = platform.outputs.sreIdentityPrincipalId
output SRE_AGENT_ID string = platform.outputs.sreAgentId
output SRE_AGENT_NAME string = platform.outputs.sreAgentName
output ACTION_GROUP_ID string = platform.outputs.actionGroupId
output METRIC_ALERT_ID string = platform.outputs.metricAlertId
