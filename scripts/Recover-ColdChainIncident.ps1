[CmdletBinding()]
param(
    [string]$SubscriptionId = '5305e853-a63b-4b82-9a3f-6fde18c1a798',
    [string]$ResourceGroup = 'rg-demo-sre-agent-v1',
    [string]$Location = 'eastus2',
    [string]$BackendAppName = 'ca-grifols-backend-v1'
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
    --set-env-vars 'DEMO_COLD_CHAIN_FAILURE_RATE=0' `
    --output none
Wait-ContainerAppReady -SubscriptionId $SubscriptionId -ResourceGroup $ResourceGroup -AppName $BackendAppName
$backendUrl = Get-ContainerAppUrl -SubscriptionId $SubscriptionId -ResourceGroup $ResourceGroup -AppName $BackendAppName
$requisition = New-SyntheticRequisition -BackendUrl $backendUrl
$response = Invoke-WebRequest `
    -Uri "$backendUrl/api/dispatch-reservations" `
    -Method Post `
    -ContentType 'application/json' `
    -Body (New-SyntheticDispatchBody -RequisitionId $requisition.id) `
    -SkipHttpErrorCheck
if ($response.StatusCode -lt 200 -or $response.StatusCode -ge 300) {
    throw "Recovery verification failed with HTTP $($response.StatusCode)."
}
$shipment = $response.Content | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($shipment.id) -or [string]::IsNullOrWhiteSpace($shipment.trackingCode)) {
    throw 'Recovery response did not contain shipment tracking details.'
}
Write-Host "Recovery confirmed. Shipment: $($shipment.id); tracking: $($shipment.trackingCode)"
