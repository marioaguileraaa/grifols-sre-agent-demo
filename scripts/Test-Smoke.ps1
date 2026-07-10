[CmdletBinding()]
param(
    [string]$SubscriptionId = '5305e853-a63b-4b82-9a3f-6fde18c1a798',
    [string]$ResourceGroup = 'rg-demo-sre-agent-v1',
    [string]$Location = 'eastus2',
    [string]$BackendAppName = 'ca-grifols-backend-v1',
    [string]$FrontendAppName = 'ca-grifols-frontend-v1'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
. (Join-Path $PSScriptRoot 'Common.ps1')

Assert-AzureTarget -SubscriptionId $SubscriptionId -ResourceGroup $ResourceGroup -Location $Location
$backendUrl = Get-ContainerAppUrl -SubscriptionId $SubscriptionId -ResourceGroup $ResourceGroup -AppName $BackendAppName
$frontendUrl = Get-ContainerAppUrl -SubscriptionId $SubscriptionId -ResourceGroup $ResourceGroup -AppName $FrontendAppName

$null = Invoke-RestMethod -Uri "$backendUrl/health"
$front = Invoke-WebRequest -Uri $frontendUrl
if ($front.StatusCode -ne 200 -or $front.Content -notmatch 'Grifols Plasma Supply') {
    throw 'Frontend smoke test failed.'
}
$centers = Invoke-RestMethod -Uri "$frontendUrl/api/distribution-centers"
if ($centers.Count -lt 3) {
    throw 'Same-origin API proxy smoke test failed.'
}
$null = Invoke-RestMethod -Uri "$frontendUrl/health"
Write-Host "Smoke test passed: $frontendUrl"
