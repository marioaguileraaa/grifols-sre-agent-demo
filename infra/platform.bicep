targetScope = 'resourceGroup'

param location string
param backendImage string
param frontendImage string

var names = {
  workspace: 'law-grifols-sre-v1'
  insights: 'appi-grifols-sre-v1'
  registry: 'acrgps${uniqueString(subscription().id, resourceGroup().name)}'
  environment: 'cae-grifols-sre-v1'
  appPullIdentity: 'id-grifols-app-pull-v1'
  backend: 'ca-grifols-backend-v1'
  frontend: 'ca-grifols-frontend-v1'
  sreIdentity: 'id-grifols-sre-v1'
  sreAgent: 'sre-agent-grifols-v1'
  actionGroup: 'ag-grifols-sre-v1'
  metricAlert: 'alert-grifols-cold-chain-5xx-v1'
}

var tags = {
  purpose: 'sre-agent-demo'
  environment: 'demo'
  dataClassification: 'synthetic'
}

var helloWorldImage = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
var acrPullRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
var readerRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7')
var logAnalyticsReaderRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '73c42c96-874c-492b-b04d-ab87d138a893')
var monitoringReaderRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '43d0d8ad-25c7-4714-9337-8ba259a9fe05')
var containerAppsContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '358470bc-b56b-4d8f-8396-3db7d1314c5b')

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: names.workspace
  location: location
  tags: tags
  properties: {
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    sku: {
      name: 'PerGB2018'
    }
  }
}

resource insights 'Microsoft.Insights/components@2020-02-02' = {
  name: names.insights
  location: location
  kind: 'web'
  tags: tags
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: workspace.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: names.registry
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: any({
    adminUserEnabled: false
    anonymousPullEnabled: false
    publicNetworkAccess: 'Enabled'
  })
}

resource appPullIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: names.appPullIdentity
  location: location
  tags: tags
}

resource appPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: registry
  name: guid(registry.id, appPullIdentity.id, acrPullRoleId)
  properties: {
    roleDefinitionId: acrPullRoleId
    principalId: appPullIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: names.environment
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: workspace.properties.customerId
        sharedKey: workspace.listKeys().primarySharedKey
      }
    }
  }
}

resource backend 'Microsoft.App/containerApps@2024-03-01' = {
  name: names.backend
  location: location
  tags: union(tags, { 'azd-service-name': 'backend' })
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${appPullIdentity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerAppsEnvironment.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: backendImage == helloWorldImage ? 80 : 8080
        transport: 'auto'
        allowInsecure: false
      }
      registries: backendImage == helloWorldImage ? [] : [
        {
          server: registry.properties.loginServer
          identity: appPullIdentity.id
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'backend'
          image: backendImage
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
              value: 'https://${names.frontend}.${containerAppsEnvironment.properties.defaultDomain}'
            }
          ]
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          probes: backendImage == helloWorldImage ? [] : [
            {
              type: 'Liveness'
              httpGet: {
                path: '/health'
                port: 8080
                scheme: 'HTTP'
              }
              initialDelaySeconds: 15
              periodSeconds: 15
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/health'
                port: 8080
                scheme: 'HTTP'
              }
              initialDelaySeconds: 5
              periodSeconds: 10
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
    }
  }
  dependsOn: [
    appPullRole
  ]
}

resource frontend 'Microsoft.App/containerApps@2024-03-01' = {
  name: names.frontend
  location: location
  tags: union(tags, { 'azd-service-name': 'frontend' })
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${appPullIdentity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerAppsEnvironment.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 80
        transport: 'auto'
        allowInsecure: false
      }
      registries: frontendImage == helloWorldImage ? [] : [
        {
          server: registry.properties.loginServer
          identity: appPullIdentity.id
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'frontend'
          image: frontendImage
          env: [
            {
              name: 'BACKEND_URL'
              value: 'https://${backend.properties.configuration.ingress.fqdn}'
            }
          ]
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
          probes: frontendImage == helloWorldImage ? [] : [
            {
              type: 'Readiness'
              httpGet: {
                path: '/health'
                port: 80
                scheme: 'HTTP'
              }
              initialDelaySeconds: 5
              periodSeconds: 10
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 3
      }
    }
  }
  dependsOn: [
    appPullRole
  ]
}

resource sreIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: names.sreIdentity
  location: location
  tags: tags
}

resource sreReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, sreIdentity.id, readerRoleId)
  properties: {
    roleDefinitionId: readerRoleId
    principalId: sreIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource sreLogAnalyticsReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, sreIdentity.id, logAnalyticsReaderRoleId)
  properties: {
    roleDefinitionId: logAnalyticsReaderRoleId
    principalId: sreIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource sreMonitoringReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, sreIdentity.id, monitoringReaderRoleId)
  properties: {
    roleDefinitionId: monitoringReaderRoleId
    principalId: sreIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource sreContainerAppsContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, sreIdentity.id, containerAppsContributorRoleId)
  properties: {
    roleDefinitionId: containerAppsContributorRoleId
    principalId: sreIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource sreAgent 'Microsoft.App/agents@2026-01-01' = {
  name: names.sreAgent
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
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
    logConfiguration: {
      applicationInsightsConfiguration: {
        appId: insights.properties.AppId
      }
    }
    incidentManagementConfiguration: {
      type: 'AzMonitor'
    }
    // Supported by the 2026-01-01 service API; the bundled Bicep type is lagging the REST schema.
    #disable-next-line BCP037
    monthlyAgentUnitLimit: 1000
    upgradeChannel: 'Stable'
  }
  dependsOn: [
    sreReader
    sreLogAnalyticsReader
    sreMonitoringReader
    sreContainerAppsContributor
  ]
}

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: names.actionGroup
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'gps5xx'
    enabled: true
  }
}

resource metricAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: names.metricAlert
  location: 'global'
  tags: tags
  properties: {
    description: 'Synthetic cold-chain dispatch reservation 5xx threshold reached.'
    severity: 2
    enabled: true
    scopes: [
      backend.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    targetResourceType: 'Microsoft.App/containerApps'
    targetResourceRegion: location
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'Backend5xxRequests'
          criterionType: 'StaticThresholdCriterion'
          metricNamespace: 'Microsoft.App/containerApps'
          metricName: 'Requests'
          operator: 'GreaterThan'
          threshold: 5
          timeAggregation: 'Total'
          dimensions: [
            {
              name: 'statusCodeCategory'
              operator: 'Include'
              values: [
                '5xx'
              ]
            }
          ]
          skipMetricValidation: false
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
}

output logAnalyticsWorkspaceId string = workspace.id
output logAnalyticsWorkspaceName string = workspace.name
output applicationInsightsId string = insights.id
output applicationInsightsAppId string = insights.properties.AppId
output containerRegistryId string = registry.id
output containerRegistryName string = registry.name
output containerRegistryLoginServer string = registry.properties.loginServer
output containerAppsEnvironmentId string = containerAppsEnvironment.id
output containerAppsEnvironmentName string = containerAppsEnvironment.name
output appPullIdentityId string = appPullIdentity.id
output backendContainerAppId string = backend.id
output backendContainerAppName string = backend.name
output backendFqdn string = backend.properties.configuration.ingress.fqdn
output frontendContainerAppId string = frontend.id
output frontendContainerAppName string = frontend.name
output frontendFqdn string = frontend.properties.configuration.ingress.fqdn
output sreIdentityId string = sreIdentity.id
output sreIdentityPrincipalId string = sreIdentity.properties.principalId
output sreAgentId string = sreAgent.id
output sreAgentName string = sreAgent.name
output actionGroupId string = actionGroup.id
output metricAlertId string = metricAlert.id
