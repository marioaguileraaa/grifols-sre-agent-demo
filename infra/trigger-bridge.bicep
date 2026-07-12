targetScope = 'resourceGroup'

@description('Existing Azure SRE Agent resource name.')
param agentName string

@description('Consumption Logic App name for the authenticated external-trigger bridge.')
param bridgeName string

@description('Azure region for the Logic App bridge.')
param bridgeLocation string

@secure()
@description('Protected Azure SRE Agent HTTP trigger URL. This value is never returned as an output.')
param protectedTriggerUrl string

@description('Tags applied to the Logic App bridge.')
param tags object = {
  purpose: 'sre-agent-demo'
  environment: 'demo'
  dataClassification: 'synthetic'
}

var sreAgentStandardUserRoleId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '2d84a65a-63b2-4343-bbb6-31105d857bc1'
)

resource sreAgent 'Microsoft.App/agents@2026-01-01' existing = {
  name: agentName
}

resource bridge 'Microsoft.Logic/workflows@2019-05-01' = {
  name: bridgeName
  location: bridgeLocation
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {}
      triggers: {
        manual: {
          type: 'Request'
          kind: 'Http'
          inputs: {
            schema: {
              type: 'object'
            }
          }
        }
      }
      actions: {
        Forward_to_SRE_Agent: {
          type: 'Http'
          inputs: {
            uri: protectedTriggerUrl
            method: 'POST'
            headers: {
              'Content-Type': 'application/json'
            }
            body: '@triggerBody()'
            authentication: {
              type: 'ManagedServiceIdentity'
              audience: 'https://azuresre.dev'
            }
            retryPolicy: {
              type: 'none'
            }
          }
          runAfter: {}
        }
        Return_SRE_Agent_response: {
          type: 'Response'
          kind: 'Http'
          inputs: {
            statusCode: '@outputs(\'Forward_to_SRE_Agent\')?[\'statusCode\']'
            headers: {
              'Content-Type': '@coalesce(outputs(\'Forward_to_SRE_Agent\')?[\'headers\']?[\'Content-Type\'], outputs(\'Forward_to_SRE_Agent\')?[\'headers\']?[\'content-type\'], \'application/json\')'
            }
            body: '@outputs(\'Forward_to_SRE_Agent\')?[\'body\']'
          }
          runAfter: {
            Forward_to_SRE_Agent: [
              'Succeeded'
            ]
          }
        }
        Return_SRE_Agent_failure: {
          type: 'Response'
          kind: 'Http'
          inputs: {
            statusCode: '@coalesce(outputs(\'Forward_to_SRE_Agent\')?[\'statusCode\'], 502)'
            headers: {
              'Content-Type': '@coalesce(outputs(\'Forward_to_SRE_Agent\')?[\'headers\']?[\'Content-Type\'], outputs(\'Forward_to_SRE_Agent\')?[\'headers\']?[\'content-type\'], \'application/json\')'
            }
            body: '@coalesce(outputs(\'Forward_to_SRE_Agent\')?[\'body\'], json(\'{"error":{"code":"SRE_TRIGGER_TRANSPORT_FAILURE","message":"The SRE Agent trigger did not return an HTTP response."}}\'))'
          }
          runAfter: {
            Forward_to_SRE_Agent: [
              'Failed'
            ]
          }
        }
        Return_SRE_Agent_timeout: {
          type: 'Response'
          kind: 'Http'
          inputs: {
            statusCode: 504
            headers: {
              'Content-Type': 'application/json'
            }
            body: {
              error: {
                code: 'SRE_TRIGGER_TIMEOUT'
                message: 'The SRE Agent trigger did not respond before the bridge timeout.'
              }
            }
          }
          runAfter: {
            Forward_to_SRE_Agent: [
              'TimedOut'
            ]
          }
        }
      }
      outputs: {}
    }
  }
}

resource bridgeSreAgentStandardUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: sreAgent
  name: guid(sreAgent.id, bridge.id, sreAgentStandardUserRoleId)
  properties: {
    principalId: bridge.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: sreAgentStandardUserRoleId
  }
}

output bridgeResourceId string = bridge.id
output bridgePrincipalId string = bridge.identity.principalId
