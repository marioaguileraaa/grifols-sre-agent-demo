[CmdletBinding()]
param(
    [string]$SubscriptionId = '5305e853-a63b-4b82-9a3f-6fde18c1a798',
    [string]$ResourceGroup = 'rg-demo-sre-agent-v1',
    [string]$Location = 'eastus2',
    [string]$BackendAppName = 'ca-grifols-backend-v1',
    [ValidateRange(10, 100)][int]$RequestCount = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
. (Join-Path $PSScriptRoot 'Common.ps1')

Assert-AzureTarget -SubscriptionId $SubscriptionId -ResourceGroup $ResourceGroup -Location $Location
az containerapp update `
    --subscription $SubscriptionId `
    --resource-group $ResourceGroup `
    --name $BackendAppName `
    --set-env-vars 'DEMO_COLD_CHAIN_FAILURE_RATE=100' `
    --output none
Wait-ContainerAppReady -SubscriptionId $SubscriptionId -ResourceGroup $ResourceGroup -AppName $BackendAppName
$backendUrl = Get-ContainerAppUrl -SubscriptionId $SubscriptionId -ResourceGroup $ResourceGroup -AppName $BackendAppName

$startedAt = [DateTimeOffset]::UtcNow
for ($index = 1; $index -le $RequestCount; $index++) {
    $requisition = New-SyntheticRequisition -BackendUrl $backendUrl
    $response = Invoke-WebRequest `
        -Uri "$backendUrl/api/dispatch-reservations" `
        -Method Post `
        -ContentType 'application/json' `
        -Body (New-SyntheticDispatchBody -RequisitionId $requisition.id) `
        -SkipHttpErrorCheck
    if ($response.StatusCode -ne 503) {
        throw "Expected HTTP 503 for request $index; received $($response.StatusCode)."
    }
    $body = $response.Content | ConvertFrom-Json
    if ($body.code -ne 'COLD_CHAIN_GATEWAY_UNAVAILABLE' -or [string]::IsNullOrWhiteSpace($body.correlationId)) {
        throw "Request $index did not return the expected structured failure."
    }
    Write-Host "Failure $index correlation ID: $($body.correlationId)"
}

if ([DateTimeOffset]::UtcNow - $startedAt -gt [TimeSpan]::FromMinutes(5)) {
    throw 'Synthetic failures took longer than the five-minute alert window.'
}
Write-Host "Synthetic incident started with $RequestCount valid failures."
