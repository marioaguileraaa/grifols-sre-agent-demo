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
if (-not $PSCmdlet.ShouldProcess("$SubscriptionId/$ResourceGroupName", 'Run two-pass Bicep deployment with remote ACR builds and smoke tests')) {
    return
}

$repoRoot = Split-Path $PSScriptRoot -Parent
$initialDeploymentName = "grifols-sre-initial-$ImageTag"
$finalDeploymentName = "grifols-sre-final-$ImageTag"

az deployment group create `
    --subscription $SubscriptionId `
    --resource-group $ResourceGroupName `
    --name $initialDeploymentName `
    --template-file "$repoRoot\infra\main.bicep" `
    --parameters environmentName=grifols-sre-demo location=$Location resourceGroupName=$ResourceGroupName `
    --output none
if ($LASTEXITCODE -ne 0) {
    throw 'Initial placeholder infrastructure deployment failed.'
}

$initialOutputs = az deployment group show `
    --subscription $SubscriptionId `
    --resource-group $ResourceGroupName `
    --name $initialDeploymentName `
    --query properties.outputs `
    --output json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to read initial deployment outputs.'
}

$registryName = $initialOutputs.AZURE_CONTAINER_REGISTRY_NAME.value
$registryServer = $initialOutputs.AZURE_CONTAINER_REGISTRY_ENDPOINT.value
$backendImage = "$registryServer/grifols-supply-api:$ImageTag"
$frontendImage = "$registryServer/grifols-supply-web:$ImageTag"

az acr build `
    --subscription $SubscriptionId `
    --registry $registryName `
    --image "grifols-supply-api:$ImageTag" `
    "$repoRoot\GrifolsSupply.Api"
if ($LASTEXITCODE -ne 0) {
    throw 'Remote backend image build failed.'
}

az acr build `
    --subscription $SubscriptionId `
    --registry $registryName `
    --image "grifols-supply-web:$ImageTag" `
    "$repoRoot\grifols-supply-frontend"
if ($LASTEXITCODE -ne 0) {
    throw 'Remote frontend image build failed.'
}

az deployment group create `
    --subscription $SubscriptionId `
    --resource-group $ResourceGroupName `
    --name $finalDeploymentName `
    --template-file "$repoRoot\infra\main.bicep" `
    --parameters `
        environmentName=grifols-sre-demo `
        location=$Location `
        resourceGroupName=$ResourceGroupName `
        apiImage=$backendImage `
        frontendImage=$frontendImage `
    --output none
if ($LASTEXITCODE -ne 0) {
    throw 'Final image infrastructure deployment failed.'
}

$finalOutputs = az deployment group show `
    --subscription $SubscriptionId `
    --resource-group $ResourceGroupName `
    --name $finalDeploymentName `
    --query properties.outputs `
    --output json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to read final deployment outputs.'
}

Wait-ContainerAppRevision `
    -SubscriptionId $SubscriptionId `
    -ResourceGroupName $ResourceGroupName `
    -ContainerAppName $BackendAppName | Out-Null
Wait-ContainerAppRevision `
    -SubscriptionId $SubscriptionId `
    -ResourceGroupName $ResourceGroupName `
    -ContainerAppName $FrontendAppName | Out-Null

$backendOrigin = $finalOutputs.API_BASE_URL.value
$frontendOrigin = $finalOutputs.FRONTEND_URL.value

$backendHealth = Invoke-WebRequest `
    -Method Get `
    -Uri "$backendOrigin/healthz" `
    -SkipHttpErrorCheck
if ($backendHealth.StatusCode -ne 200) {
    throw "Backend health smoke expected HTTP 200 but received $($backendHealth.StatusCode)."
}

$dispatchResponse = Invoke-WebRequest `
    -Method Post `
    -Uri "$backendOrigin/api/cold-chain-dispatch" `
    -ContentType 'application/json' `
    -Body ((New-DemoDispatchPayload) | ConvertTo-Json -Depth 8) `
    -SkipHttpErrorCheck
if ($dispatchResponse.StatusCode -ne 201) {
    throw "Healthy dispatch smoke expected HTTP 201 but received $($dispatchResponse.StatusCode): $($dispatchResponse.Content)"
}
$shipment = $dispatchResponse.Content | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($shipment.trackingId)) {
    throw 'Healthy dispatch smoke did not return a tracking ID.'
}

$trackingResponse = Invoke-WebRequest `
    -Method Get `
    -Uri "$backendOrigin/api/cold-chain-dispatch/$($shipment.trackingId)" `
    -SkipHttpErrorCheck
if ($trackingResponse.StatusCode -ne 200) {
    throw "Tracking smoke expected HTTP 200 but received $($trackingResponse.StatusCode)."
}
$trackedShipment = $trackingResponse.Content | ConvertFrom-Json
if ($trackedShipment.trackingId -ne $shipment.trackingId) {
    throw 'Tracking smoke returned an unexpected tracking ID.'
}

$frontendResponse = Invoke-WebRequest -Method Get -Uri "$frontendOrigin/" -SkipHttpErrorCheck
if ($frontendResponse.StatusCode -ne 200 -or $frontendResponse.Content -notmatch 'Grifols Plasma Supply') {
    throw "Frontend smoke failed. HTTP $($frontendResponse.StatusCode)."
}

$sameOriginHealth = Invoke-WebRequest `
    -Method Get `
    -Uri "$frontendOrigin/api/healthz" `
    -SkipHttpErrorCheck
if ($sameOriginHealth.StatusCode -ne 200) {
    throw "Same-origin API smoke expected HTTP 200 but received $($sameOriginHealth.StatusCode)."
}

Write-Host "Frontend: $frontendOrigin"
Write-Host "API:      $backendOrigin"
Write-Host "ACR:      $registryName"
Write-Host "Tracking: $($shipment.trackingId)"
Write-Host 'SRE Agent: sre-agent-grifols-v1'
