targetScope = 'resourceGroup'

@description('Deployment label used by Azure Developer CLI.')
param environmentName string = 'grifols-sre-demo'

@description('Azure region for all regional resources.')
param location string = 'eastus2'

@description('Existing demo resource group. Deployment updates it idempotently.')
param resourceGroupName string = 'rg-demo-sre-agent-v1'

@description('Backend image. The deployment script replaces the placeholder after remote ACR build.')
param apiImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

@description('Frontend image. The deployment script replaces the placeholder after remote ACR build.')
param frontendImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

var tags = {
  purpose: 'sre-agent-demo'
  environment: 'demo'
  dataClassification: 'synthetic'
  'azd-env-name': environmentName
}
var token = uniqueString(subscription().subscriptionId, resourceGroupName)
var registryName = 'acrgrfdemo${token}'
var environmentNameResource = 'cae-grifols-demo-v1'
var backendName = 'ca-grifols-supply-api'
var frontendName = 'ca-grifols-supply-web'
var logAnalyticsName = 'law-grifols-demo-v1'
var applicationInsightsName = 'appi-grifols-demo-v1'
var appIdentityName = 'id-grifols-app-v1'
var sreIdentityName = 'id-grifols-sre-v1'
var sreAgentName = 'sre-agent-grifols-v1'

var acrPullRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
var readerRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7')
var logAnalyticsReaderRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '73c42c96-874c-492b-b04d-ab87d138a893')
var monitoringReaderRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '43d0d8ad-25c7-4714-9337-8ba259a9fe05')
var containerAppsContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '358470bc-b998-42bd-ab17-a7e34c199c0f')
var monitoringContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '749f88d5-cbae-40b8-bcfc-e573ddc772fa')

module observability 'core/observability.bicep' = {
  name: 'observability'
  params: {
    location: location
    logAnalyticsName: logAnalyticsName
    applicationInsightsName: applicationInsightsName
    tags: tags
  }
}

module registry 'core/host/container-registry.bicep' = {
  name: 'registry'
  params: {
    name: registryName
    location: location
    tags: tags
  }
}

resource appIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: appIdentityName
  location: location
  tags: tags
}

resource sreIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: sreIdentityName
  location: location
  tags: tags
}

resource registryExisting 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: registryName
}

resource appAcrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: registryExisting
  name: guid(registryExisting.id, appIdentity.id, acrPullRoleId)
  properties: {
    principalId: appIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: acrPullRoleId
  }
  dependsOn: [
    registry
  ]
}

module containerEnvironment 'core/host/container-apps-environment.bicep' = {
  name: 'container-environment'
  params: {
    name: environmentNameResource
    location: location
    tags: tags
    logAnalyticsCustomerId: observability.outputs.workspaceCustomerId
    logAnalyticsSharedKey: observability.outputs.workspaceSharedKey
  }
}

module backend 'core/host/container-app.bicep' = {
  name: 'backend'
  params: {
    name: backendName
    location: location
    tags: union(tags, { 'azd-service-name': 'api' })
    environmentId: containerEnvironment.outputs.id
    registryServer: registry.outputs.loginServer
    managedIdentityId: appIdentity.id
    containerName: 'grifols-supply-api'
    containerImage: apiImage
    targetPort: 8080
    maxReplicas: 1
    env: [
      {
        name: 'ASPNETCORE_ENVIRONMENT'
        value: 'Production'
      }
      {
        name: 'DEMO_COLD_CHAIN_FAILURE_RATE'
        value: '0'
      }
      {
        name: 'AllowedOrigins__0'
        value: 'https://${frontendName}.${containerEnvironment.outputs.defaultDomain}'
      }
    ]
  }
  dependsOn: [
    appAcrPull
  ]
}

module frontend 'core/host/container-app.bicep' = {
  name: 'frontend'
  params: {
    name: frontendName
    location: location
    tags: union(tags, { 'azd-service-name': 'frontend' })
    environmentId: containerEnvironment.outputs.id
    registryServer: registry.outputs.loginServer
    managedIdentityId: appIdentity.id
    containerName: 'grifols-supply-web'
    containerImage: frontendImage
    targetPort: 80
    env: [
      {
        name: 'REACT_APP_API_BASE_URL'
        value: 'https://${backend.outputs.fqdn}/api'
      }
    ]
  }
  dependsOn: [
    appAcrPull
  ]
}

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'ag-grifols-sre-demo'
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'grifols-sre'
    enabled: true
  }
}

resource backendResource 'Microsoft.App/containerApps@2024-03-01' existing = {
  name: backendName
}

resource fiveXxAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alert-grifols-backend-5xx'
  location: 'global'
  tags: tags
  properties: {
    description: 'Fictional Grifols demo backend emitted more than five HTTP 5xx responses in five minutes.'
    severity: 2
    enabled: true
    scopes: [
      backendResource.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    targetResourceType: 'Microsoft.App/containerApps'
    targetResourceRegion: location
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'Backend5xx'
          metricNamespace: 'Microsoft.App/containerApps'
          metricName: 'Requests'
          operator: 'GreaterThan'
          threshold: 5
          timeAggregation: 'Total'
          criterionType: 'StaticThresholdCriterion'
          dimensions: [
            {
              name: 'statusCodeCategory'
              operator: 'Include'
              values: [
                '5xx'
              ]
            }
          ]
        }
      ]
    }
    autoMitigate: true
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
  dependsOn: [
    backend
  ]
}

resource sreReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, sreIdentity.id, readerRoleId)
  properties: {
    principalId: sreIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: readerRoleId
  }
}

resource sreLogReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, sreIdentity.id, logAnalyticsReaderRoleId)
  properties: {
    principalId: sreIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: logAnalyticsReaderRoleId
  }
}

resource sreMonitoringReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, sreIdentity.id, monitoringReaderRoleId)
  properties: {
    principalId: sreIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: monitoringReaderRoleId
  }
}

resource sreContainerAppsContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, sreIdentity.id, containerAppsContributorRoleId)
  properties: {
    principalId: sreIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: containerAppsContributorRoleId
  }
}

module sreMonitoringContributor 'core/subscription-role-assignment.bicep' = {
  name: 'sre-monitoring-contributor'
  scope: subscription()
  params: {
    principalId: sreIdentity.properties.principalId
    roleDefinitionId: monitoringContributorRoleId
    principalType: 'ServicePrincipal'
  }
}

resource sreAgent 'Microsoft.App/agents@2026-01-01' = {
  name: sreAgentName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned, UserAssigned'
    userAssignedIdentities: {
      '${sreIdentity.id}': {}
    }
  }
  properties: {
    actionConfiguration: {
      accessLevel: 'Low'
      identity: sreIdentity.id
      mode: 'Review'
    }
    knowledgeGraphConfiguration: {
      identity: sreIdentity.id
      managedResources: [
        resourceGroup().id
      ]
    }
    defaultModel: {
      provider: 'Anthropic'
      name: 'Automatic'
    }
    incidentManagementConfiguration: {
      type: 'AzMonitor'
      connectionName: 'azmonitor'
    }
    logConfiguration: {
      applicationInsightsConfiguration: {
        appId: observability.outputs.applicationInsightsAppId
        connectionString: observability.outputs.applicationInsightsConnectionString
      }
    }
    upgradeChannel: 'Preview'
  }
  dependsOn: [
    sreReader
    sreLogReader
    sreMonitoringReader
    sreContainerAppsContributor
    sreMonitoringContributor
    fiveXxAlert
  ]
}

resource logAnalyticsConnector 'Microsoft.App/agents/connectors@2025-05-01-preview' = {
  parent: sreAgent
  name: 'log-analytics'
  properties: {
    dataConnectorType: 'LogAnalytics'
    dataSource: observability.outputs.workspaceId
    extendedProperties: {
      armResourceId: observability.outputs.workspaceId
      resource: {
        name: observability.outputs.workspaceName
      }
    }
    identity: 'system'
  }
}

resource appInsightsConnector 'Microsoft.App/agents/connectors@2025-05-01-preview' = {
  parent: sreAgent
  name: 'application-insights'
  properties: {
    dataConnectorType: 'AppInsights'
    dataSource: observability.outputs.applicationInsightsId
    extendedProperties: {
      armResourceId: observability.outputs.applicationInsightsId
      resource: {
        name: observability.outputs.applicationInsightsName
      }
      appId: observability.outputs.applicationInsightsAppId
    }
    identity: 'system'
  }
}

output AZURE_LOCATION string = location
output AZURE_RESOURCE_GROUP string = resourceGroup().name
output AZURE_CONTAINER_REGISTRY_NAME string = registry.outputs.name
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = registry.outputs.loginServer
output API_BASE_URL string = 'https://${backend.outputs.fqdn}'
output FRONTEND_URL string = 'https://${frontend.outputs.fqdn}'
output LOG_ANALYTICS_WORKSPACE_ID string = observability.outputs.workspaceId
output APPLICATION_INSIGHTS_ID string = observability.outputs.applicationInsightsId
output SRE_AGENT_ID string = sreAgent.id
output SRE_AGENT_IDENTITY_CLIENT_ID string = sreIdentity.properties.clientId
