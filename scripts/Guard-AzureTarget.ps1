[CmdletBinding()]
param(
    [string]$SubscriptionId = '5305e853-a63b-4b82-9a3f-6fde18c1a798',
    [string]$ResourceGroup = 'rg-demo-sre-agent-v1',
    [string]$Location = 'eastus2'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
. (Join-Path $PSScriptRoot 'Common.ps1')

Assert-Command -Name 'npm'
Assert-AzureTarget -SubscriptionId $SubscriptionId -ResourceGroup $ResourceGroup -Location $Location

$providers = @('Microsoft.App', 'Microsoft.ContainerRegistry', 'Microsoft.Insights', 'Microsoft.OperationalInsights', 'Microsoft.ManagedIdentity')
foreach ($provider in $providers) {
    $state = az provider show --namespace $provider --subscription $SubscriptionId --query registrationState --output tsv
    if ($state -ne 'Registered') {
        throw "Required resource provider '$provider' is not registered."
    }
}

Write-Host 'Prerequisite and target guard completed successfully.'
