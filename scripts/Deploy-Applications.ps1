[CmdletBinding()]
param(
    [string]$SubscriptionId = '5305e853-a63b-4b82-9a3f-6fde18c1a798',
    [string]$ResourceGroup = 'rg-demo-sre-agent-v1',
    [string]$Location = 'eastus2',
    [string]$BackendAppName = 'ca-grifols-backend-v1',
    [string]$FrontendAppName = 'ca-grifols-frontend-v1',
    [string]$AppPullIdentityName = 'id-grifols-app-pull-v1',
    [string]$ImageTag = (Get-Date -AsUTC -Format 'yyyyMMddHHmmss')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
. (Join-Path $PSScriptRoot 'Common.ps1')

Assert-AzureTarget -SubscriptionId $SubscriptionId -ResourceGroup $ResourceGroup -Location $Location
$repoRoot = Split-Path $PSScriptRoot -Parent
$registryName = az acr list `
    --subscription $SubscriptionId `
    --resource-group $ResourceGroup `
    --query "[?tags.purpose=='sre-agent-demo'].name | [0]" `
    --output tsv
if ([string]::IsNullOrWhiteSpace($registryName)) {
    throw 'The demo Azure Container Registry was not found.'
}

$loginServer = az acr show --name $registryName --subscription $SubscriptionId --query loginServer --output tsv
$pullIdentityId = az identity show `
    --subscription $SubscriptionId `
    --resource-group $ResourceGroup `
    --name $AppPullIdentityName `
    --query id `
    --output tsv

Push-Location $repoRoot
try {
    az acr build `
        --subscription $SubscriptionId `
        --registry $registryName `
        --image "grifols-plasma-backend:$ImageTag" `
        --file 'GrifolsPlasmaSupply.Api/Dockerfile' `
        'GrifolsPlasmaSupply.Api'
    az acr build `
        --subscription $SubscriptionId `
        --registry $registryName `
        --image "grifols-plasma-frontend:$ImageTag" `
        --file 'grifols-plasma-supply-frontend/Dockerfile' `
        'grifols-plasma-supply-frontend'
}
finally {
    Pop-Location
}

foreach ($appName in @($BackendAppName, $FrontendAppName)) {
    az containerapp registry set `
        --subscription $SubscriptionId `
        --resource-group $ResourceGroup `
        --name $appName `
        --server $loginServer `
        --identity $pullIdentityId `
        --output none
}

az containerapp update `
    --subscription $SubscriptionId `
    --resource-group $ResourceGroup `
    --name $BackendAppName `
    --image "$loginServer/grifols-plasma-backend:$ImageTag" `
    --set-env-vars 'DEMO_COLD_CHAIN_FAILURE_RATE=0' `
    --output none
Wait-ContainerAppReady -SubscriptionId $SubscriptionId -ResourceGroup $ResourceGroup -AppName $BackendAppName

$backendUrl = Get-ContainerAppUrl -SubscriptionId $SubscriptionId -ResourceGroup $ResourceGroup -AppName $BackendAppName
az containerapp update `
    --subscription $SubscriptionId `
    --resource-group $ResourceGroup `
    --name $FrontendAppName `
    --image "$loginServer/grifols-plasma-frontend:$ImageTag" `
    --set-env-vars "BACKEND_URL=$backendUrl" `
    --output none
Wait-ContainerAppReady -SubscriptionId $SubscriptionId -ResourceGroup $ResourceGroup -AppName $FrontendAppName

& (Join-Path $PSScriptRoot 'Test-Smoke.ps1') `
    -SubscriptionId $SubscriptionId `
    -ResourceGroup $ResourceGroup `
    -Location $Location `
    -BackendAppName $BackendAppName `
    -FrontendAppName $FrontendAppName
