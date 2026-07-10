[CmdletBinding()]
param(
    [string]$SubscriptionId = '5305e853-a63b-4b82-9a3f-6fde18c1a798',
    [string]$ResourceGroup = 'rg-demo-sre-agent-v1',
    [string]$Location = 'eastus2',
    [string]$AgentName = 'sre-agent-grifols-v1',
    [ValidateRange(1, 10000)][int]$MonthlyAgentUnitLimit = 1000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
$ProgressPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'Common.ps1')

Assert-AzureTarget -SubscriptionId $SubscriptionId -ResourceGroup $ResourceGroup -Location $Location
$agentId = az resource show `
    --subscription $SubscriptionId `
    --resource-group $ResourceGroup `
    --resource-type 'Microsoft.App/agents' `
    --name $AgentName `
    --api-version '2026-01-01' `
    --query id `
    --output tsv
if ([string]::IsNullOrWhiteSpace($agentId)) {
    throw "SRE Agent '$AgentName' was not found."
}

$workspaceId = az monitor log-analytics workspace show `
    --subscription $SubscriptionId `
    --resource-group $ResourceGroup `
    --workspace-name 'law-grifols-sre-v1' `
    --query id `
    --output tsv
$previewBase = "https://management.azure.com${agentId}"
$agentProperties = az rest `
    --method Get `
    --url "$previewBase?api-version=2025-05-01-preview" `
    --output json | ConvertFrom-Json
$agentEndpoint = $agentProperties.properties.agentEndpoint
$sreIdentityId = $agentProperties.properties.actionConfiguration.identity
if ([string]::IsNullOrWhiteSpace($agentEndpoint) -or [string]::IsNullOrWhiteSpace($sreIdentityId)) {
    throw 'The SRE Agent endpoint or action identity could not be discovered.'
}

$token = az account get-access-token `
    --subscription $SubscriptionId `
    --resource 'https://azuresre.dev' `
    --query accessToken `
    --output tsv
if ([string]::IsNullOrWhiteSpace($token)) {
    throw 'A runtime Azure SRE access token could not be acquired.'
}

$headers = @{
    Authorization = "Bearer $token"
    Accept = 'application/json'
}
$configRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'sre-config'

try {
    $logConnector = @{
        properties = @{
            name = 'log-analytics-grifols-demo'
            dataConnectorType = 'Kusto'
            dataSource = $workspaceId
            identity = $sreIdentityId
        }
    } | ConvertTo-Json -Depth 10 -Compress
    $githubConnector = @{
        properties = @{
            name = 'github-grifols-demo'
            dataConnectorType = 'GitHubOAuth'
            dataSource = 'github-oauth'
        }
    } | ConvertTo-Json -Depth 10 -Compress
    az rest --method Put --url "$previewBase/DataConnectors/log-analytics-grifols-demo?api-version=2025-05-01-preview" --body $logConnector --output none
    az rest --method Put --url "$previewBase/DataConnectors/github-grifols-demo?api-version=2025-05-01-preview" --body $githubConnector --output none

    $repository = @{
        name = 'grifols-sre-agent-demo'
        type = 'CodeRepo'
        properties = @{
            url = 'https://github.com/marioaguileraaa/grifols-sre-agent-demo'
            authConnectorName = 'github-grifols-demo'
        }
    } | ConvertTo-Json -Depth 10 -Compress
    $null = Invoke-RestMethod `
        -Uri "$agentEndpoint/api/v2/repos/grifols-sre-agent-demo" `
        -Method Put `
        -Headers $headers `
        -ContentType 'application/json' `
        -Body $repository

    $subagentSpec = Get-Content (Join-Path $configRoot 'code-analyzer.json') -Raw
    $subagentBody = @{
        properties = @{
            value = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($subagentSpec))
        }
    } | ConvertTo-Json -Depth 10 -Compress
    az rest --method Put --url "$previewBase/subagents/code-analyzer?api-version=2025-05-01-preview" --body $subagentBody --output none

    $limitBody = @{
        properties = @{
            monthlyAgentUnitLimit = $MonthlyAgentUnitLimit
        }
    } | ConvertTo-Json -Depth 5 -Compress
    az rest --method Patch --url "$previewBase?api-version=2025-05-01-preview" --body $limitBody --output none

    $null = Invoke-RestMethod `
        -Uri "$agentEndpoint/api/v2/repos/grifols-sre-agent-demo" `
        -Method Get `
        -Headers $headers
    $configuredLimit = az rest `
        --method Get `
        --url "$previewBase?api-version=2025-05-01-preview" `
        --query properties.monthlyAgentUnitLimit `
        --output tsv
    if ([int]$configuredLimit -ne $MonthlyAgentUnitLimit) {
        throw "Expected monthly agent unit limit $MonthlyAgentUnitLimit, found $configuredLimit."
    }
}
finally {
    $headers.Authorization = $null
    $token = $null
}

Write-Host 'Declarative SRE Agent configuration and monthly unit limit verified.'
Write-Warning 'Manual step remains: complete GitHub OAuth consent interactively in the Azure portal. No OAuth token or PAT is stored by this script.'
