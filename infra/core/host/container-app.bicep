param name string
param location string = resourceGroup().location
param tags object
param environmentId string
param registryServer string
param managedIdentityId string
param containerName string
param containerImage string
param targetPort int
param env array = []
param cpu string = '0.5'
param memory string = '1.0Gi'
param maxReplicas int = 2

resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityId}': {}
    }
  }
  properties: {
    managedEnvironmentId: environmentId
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: targetPort
        transport: 'auto'
        allowInsecure: false
      }
      registries: [
        {
          server: registryServer
          identity: managedIdentityId
        }
      ]
    }
    template: {
      containers: [
        {
          name: containerName
          image: containerImage
          env: env
          resources: {
            cpu: json(cpu)
            memory: memory
          }
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: maxReplicas
      }
    }
  }
}

output id string = containerApp.id
output name string = containerApp.name
output fqdn string = containerApp.properties.configuration.ingress.fqdn
