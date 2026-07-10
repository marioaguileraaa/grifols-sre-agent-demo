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

function Invoke-DemoBicepDeployment {
    param(
        [Parameter(Mandatory)]
        [string] $Name,
        [string] $ApiImage,
        [string] $FrontendImage
    )

    $arguments = @(
        'deployment', 'group', 'create',
        '--subscription', $SubscriptionId,
        '--resource-group', $ResourceGroupName,
        '--name', $Name,
        '--template-file', "$repoRoot\infra\main.bicep",
        '--parameters',
        'environmentName=grifols-sre-demo',
        "location=$Location",
        "resourceGroupName=$ResourceGroupName"
    )
    if (-not [string]::IsNullOrWhiteSpace($ApiImage) -and -not [string]::IsNullOrWhiteSpace($FrontendImage)) {
        $arguments += "apiImage=$ApiImage"
        $arguments += "frontendImage=$FrontendImage"
    }
    $arguments += @('--output', 'none')

    az @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Bicep deployment '$Name' failed."
    }
}

Assert-DemoAzureContext -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName
if (-not $PSCmdlet.ShouldProcess("$SubscriptionId/$ResourceGroupName", 'Run the two-pass infrastructure and application deployment')) {
    return
}

$repoRoot = Split-Path $PSScriptRoot -Parent
$bootstrapDeploymentName = "grifols-sre-demo-$ImageTag-bootstrap"
$finalDeploymentName = "grifols-sre-demo-$ImageTag-final"

Invoke-DemoBicepDeployment -Name $bootstrapDeploymentName

$bootstrapOutputs = az deployment group show `
    --subscription $SubscriptionId `
    --resource-group $ResourceGroupName `
    --name $bootstrapDeploymentName `
    --query properties.outputs `
    --output json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to read initial deployment outputs.'
}

$registryName = $bootstrapOutputs.AZURE_CONTAINER_REGISTRY_NAME.value
$registryServer = $bootstrapOutputs.AZURE_CONTAINER_REGISTRY_ENDPOINT.value
$backendImage = "$registryServer/grifols-supply-api:$ImageTag"
$frontendImage = "$registryServer/grifols-supply-web:$ImageTag"

az acr build --subscription $SubscriptionId --registry $registryName --image "grifols-supply-api:$ImageTag" "$repoRoot\GrifolsSupply.Api"
if ($LASTEXITCODE -ne 0) {
    throw 'Remote backend image build failed.'
}

az acr build --subscription $SubscriptionId --registry $registryName --image "grifols-supply-web:$ImageTag" "$repoRoot\grifols-supply-frontend"
if ($LASTEXITCODE -ne 0) {
    throw 'Remote frontend image build failed.'
}

Invoke-DemoBicepDeployment `
    -Name $finalDeploymentName `
    -ApiImage $backendImage `
    -FrontendImage $frontendImage

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

$failureRate = az containerapp show `
    --subscription $SubscriptionId `
    --resource-group $ResourceGroupName `
    --name $BackendAppName `
    --query "properties.template.containers[0].env[?name=='DEMO_COLD_CHAIN_FAILURE_RATE'].value | [0]" `
    --output tsv
if ($LASTEXITCODE -ne 0 -or $failureRate -ne '0') {
    throw "Final backend configuration must keep DEMO_COLD_CHAIN_FAILURE_RATE=0. Reported: '$failureRate'."
}

$apiBaseUrl = $finalOutputs.API_BASE_URL.value.TrimEnd('/')
$frontendUrl = $finalOutputs.FRONTEND_URL.value.TrimEnd('/')

$healthResponse = Invoke-WebRequest -Method Get -Uri "$apiBaseUrl/healthz" -SkipHttpErrorCheck
if ($healthResponse.StatusCode -ne 200) {
    throw "API health smoke test expected HTTP 200 but received $($healthResponse.StatusCode)."
}

$dispatchResponse = Invoke-WebRequest `
    -Method Post `
    -Uri "$apiBaseUrl/api/cold-chain-dispatch" `
    -ContentType 'application/json' `
    -Body ((New-DemoDispatchPayload) | ConvertTo-Json -Depth 8) `
    -SkipHttpErrorCheck
if ($dispatchResponse.StatusCode -ne 201) {
    throw "Healthy dispatch smoke test expected HTTP 201 but received $($dispatchResponse.StatusCode): $($dispatchResponse.Content)"
}

$shipment = $dispatchResponse.Content | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($shipment.trackingId)) {
    throw 'Healthy dispatch smoke test did not return a tracking ID.'
}

$encodedTrackingId = [Uri]::EscapeDataString($shipment.trackingId)
$trackingResponse = Invoke-WebRequest `
    -Method Get `
    -Uri "$apiBaseUrl/api/cold-chain-dispatch/$encodedTrackingId" `
    -SkipHttpErrorCheck
if ($trackingResponse.StatusCode -ne 200) {
    throw "Shipment tracking smoke test expected HTTP 200 but received $($trackingResponse.StatusCode)."
}

$trackedShipment = $trackingResponse.Content | ConvertFrom-Json
if ($trackedShipment.trackingId -ne $shipment.trackingId) {
    throw 'Shipment tracking smoke test returned a different tracking ID.'
}

$frontendResponse = Invoke-WebRequest -Method Get -Uri $frontendUrl -SkipHttpErrorCheck
if ($frontendResponse.StatusCode -ne 200) {
    throw "Frontend smoke test expected HTTP 200 but received $($frontendResponse.StatusCode)."
}

$sameOriginResponse = Invoke-WebRequest -Method Get -Uri "$frontendUrl/api/healthz" -SkipHttpErrorCheck
if ($sameOriginResponse.StatusCode -ne 200) {
    throw "Same-origin frontend API smoke test expected HTTP 200 but received $($sameOriginResponse.StatusCode)."
}

Write-Host "Frontend: $frontendUrl"
Write-Host "API:      $apiBaseUrl"
Write-Host "ACR:      $registryName"
Write-Host 'SRE Agent: sre-agent-grifols-v1'
Write-Host "Healthy dispatch and tracking verified. trackingId=$($shipment.trackingId)"
