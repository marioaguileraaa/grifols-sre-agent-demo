#requires -Version 7.2
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $SubscriptionId = '5305e853-a63b-4b82-9a3f-6fde18c1a798',
    [string] $ResourceGroupName = 'rg-demo-sre-agent-v1',
    [string] $Location = 'eastus2',
    [string] $BackendAppName = 'ca-grifols-supply-api',
    [string] $FrontendAppName = 'ca-grifols-supply-web',
    [string] $ImageTag = (Get-Date -Format 'yyyyMMddHHmmss')
)

. "$PSScriptRoot\AzureDemo.Common.ps1"

Assert-DemoAzureContext -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName
if (-not $PSCmdlet.ShouldProcess("$SubscriptionId/$ResourceGroupName", 'Provision infrastructure and build/update both apps')) {
    return
}

$repoRoot = Split-Path $PSScriptRoot -Parent
$deploymentName = "grifols-sre-demo-$ImageTag"
az deployment group create `
    --subscription $SubscriptionId `
    --resource-group $ResourceGroupName `
    --name $deploymentName `
    --template-file "$repoRoot\infra\main.bicep" `
    --parameters environmentName=grifols-sre-demo location=$Location resourceGroupName=$ResourceGroupName `
    --output none
if ($LASTEXITCODE -ne 0) {
    throw 'Infrastructure deployment failed.'
}

$outputs = az deployment group show `
    --subscription $SubscriptionId `
    --resource-group $ResourceGroupName `
    --name $deploymentName `
    --query properties.outputs `
    --output json | ConvertFrom-Json
$registryName = $outputs.AZURE_CONTAINER_REGISTRY_NAME.value
$registryServer = $outputs.AZURE_CONTAINER_REGISTRY_ENDPOINT.value
$backendImage = "$registryServer/grifols-supply-api:$ImageTag"
$frontendImage = "$registryServer/grifols-supply-web:$ImageTag"

az acr build --subscription $SubscriptionId --registry $registryName --image "grifols-supply-api:$ImageTag" "$repoRoot\GrifolsSupply.Api"
if ($LASTEXITCODE -ne 0) { throw 'Remote backend image build failed.' }
az acr build --subscription $SubscriptionId --registry $registryName --image "grifols-supply-web:$ImageTag" "$repoRoot\grifols-supply-frontend"
if ($LASTEXITCODE -ne 0) { throw 'Remote frontend image build failed.' }

az containerapp update `
    --subscription $SubscriptionId `
    --resource-group $ResourceGroupName `
    --name $BackendAppName `
    --image $backendImage `
    --set-env-vars DEMO_COLD_CHAIN_FAILURE_RATE=0 `
    --output none
if ($LASTEXITCODE -ne 0) { throw 'Backend update failed.' }
Wait-ContainerAppRevision -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -ContainerAppName $BackendAppName | Out-Null

$backendFqdn = az containerapp show `
    --subscription $SubscriptionId `
    --resource-group $ResourceGroupName `
    --name $BackendAppName `
    --query properties.configuration.ingress.fqdn `
    --output tsv
az containerapp update `
    --subscription $SubscriptionId `
    --resource-group $ResourceGroupName `
    --name $FrontendAppName `
    --image $frontendImage `
    --set-env-vars "REACT_APP_API_BASE_URL=https://$backendFqdn/api" `
    --output none
if ($LASTEXITCODE -ne 0) { throw 'Frontend update failed.' }
Wait-ContainerAppRevision -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -ContainerAppName $FrontendAppName | Out-Null

$frontendFqdn = az containerapp show `
    --subscription $SubscriptionId `
    --resource-group $ResourceGroupName `
    --name $FrontendAppName `
    --query properties.configuration.ingress.fqdn `
    --output tsv
Write-Host "Frontend: https://$frontendFqdn"
Write-Host "API:      https://$backendFqdn"
Write-Host "ACR:      $registryName"
Write-Host "SRE Agent: sre-agent-grifols-v1"
