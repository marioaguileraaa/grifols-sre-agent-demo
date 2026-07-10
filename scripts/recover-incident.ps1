#requires -Version 7.2
[CmdletBinding()]
param(
    [string] $SubscriptionId = '5305e853-a63b-4b82-9a3f-6fde18c1a798',
    [string] $ResourceGroupName = 'rg-demo-sre-agent-v1',
    [string] $BackendAppName = 'ca-grifols-supply-api'
)

. "$PSScriptRoot\AzureDemo.Common.ps1"

Assert-DemoAzureContext -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName
az containerapp update `
    --subscription $SubscriptionId `
    --resource-group $ResourceGroupName `
    --name $BackendAppName `
    --set-env-vars DEMO_COLD_CHAIN_FAILURE_RATE=0 `
    --output none
if ($LASTEXITCODE -ne 0) {
    throw 'Failed to disable the deterministic incident.'
}

Wait-ContainerAppRevision `
    -SubscriptionId $SubscriptionId `
    -ResourceGroupName $ResourceGroupName `
    -ContainerAppName $BackendAppName | Out-Null

$fqdn = az containerapp show `
    --subscription $SubscriptionId `
    --resource-group $ResourceGroupName `
    --name $BackendAppName `
    --query properties.configuration.ingress.fqdn `
    --output tsv
$response = Invoke-WebRequest `
    -Method Post `
    -Uri "https://$fqdn/api/cold-chain-dispatch" `
    -ContentType 'application/json' `
    -Body ((New-DemoDispatchPayload) | ConvertTo-Json -Depth 8) `
    -SkipHttpErrorCheck
if ($response.StatusCode -ne 201) {
    throw "Recovery smoke test expected HTTP 201 but received $($response.StatusCode): $($response.Content)"
}

$shipment = $response.Content | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($shipment.trackingId)) {
    throw 'Recovery response did not contain a tracking ID.'
}

Write-Host "Recovery verified. trackingId=$($shipment.trackingId) correlationId=$($shipment.correlationId)"
