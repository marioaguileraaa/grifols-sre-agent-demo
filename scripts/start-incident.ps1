#requires -Version 7.2
[CmdletBinding()]
param(
    [string] $SubscriptionId = '5305e853-a63b-4b82-9a3f-6fde18c1a798',
    [string] $ResourceGroupName = 'rg-demo-sre-agent-v1',
    [string] $BackendAppName = 'ca-grifols-supply-api',
    [int] $RequestCount = 8
)

. "$PSScriptRoot\AzureDemo.Common.ps1"

if ($RequestCount -lt 8) {
    throw 'RequestCount must be at least 8 so the >5/5m alert threshold is crossed.'
}

Assert-DemoAzureContext -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName
az containerapp update `
    --subscription $SubscriptionId `
    --resource-group $ResourceGroupName `
    --name $BackendAppName `
    --set-env-vars DEMO_COLD_CHAIN_FAILURE_RATE=100 `
    --output none
if ($LASTEXITCODE -ne 0) {
    throw 'Failed to enable the deterministic incident.'
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
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($fqdn)) {
    throw 'Unable to resolve the backend FQDN.'
}

$startedAt = Get-Date
for ($index = 1; $index -le $RequestCount; $index++) {
    if (((Get-Date) - $startedAt).TotalMinutes -ge 5) {
        throw 'Failed requests were not completed within five minutes.'
    }

    $payload = New-DemoDispatchPayload
    $response = Invoke-WebRequest `
        -Method Post `
        -Uri "https://$fqdn/api/cold-chain-dispatch" `
        -ContentType 'application/json' `
        -Body ($payload | ConvertTo-Json -Depth 8) `
        -SkipHttpErrorCheck
    if ($response.StatusCode -ne 503) {
        throw "Request $index expected HTTP 503 but received $($response.StatusCode)."
    }

    $failure = $response.Content | ConvertFrom-Json
    if ($failure.code -ne 'COLD_CHAIN_GATEWAY_UNAVAILABLE' -or [string]::IsNullOrWhiteSpace($failure.correlationId)) {
        throw "Request $index returned an unexpected failure contract."
    }

    Write-Host "[$index/$RequestCount] 503 correlationId=$($failure.correlationId)"
}

Write-Host "Incident started: $RequestCount deterministic failures in $([Math]::Round(((Get-Date) - $startedAt).TotalSeconds, 1)) seconds."
