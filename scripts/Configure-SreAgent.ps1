[CmdletBinding()]
param(
    [string]$SubscriptionId = '5305e853-a63b-4b82-9a3f-6fde18c1a798',
    [string]$ResourceGroup = 'rg-demo-sre-agent-v1',
    [string]$Location = 'eastus2',
    [string]$AgentName = 'sre-agent-grifols-v1',
    [string]$BackendAppName = 'ca-grifols-backend-v1',
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
$agentBase = "https://management.azure.com${agentId}"
$agentProperties = az rest `
    --method Get `
    --url "$agentBase?api-version=2026-01-01" `
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

function Invoke-DataPlanePut {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][object]$Body
    )
    $null = Invoke-RestMethod `
        -Uri "$agentEndpoint$Path" `
        -Method Put `
        -Headers $headers `
        -ContentType 'application/json' `
        -Body ($Body | ConvertTo-Json -Depth 20 -Compress)
}

try {
    $logConnector = @{
        properties = @{
            name = 'log-analytics-grifols-demo'
            dataConnectorType = 'Kusto'
            dataSource = $workspaceId
            identity = $sreIdentityId
        }
    } | ConvertTo-Json -Depth 10 -Compress
    az rest `
        --method Put `
        --url "$agentBase/DataConnectors/log-analytics-grifols-demo?api-version=2025-05-01-preview" `
        --body $logConnector `
        --output none

    $domains = Invoke-RestMethod -Uri "$agentEndpoint/api/v2/github/domains" -Method Get -Headers $headers
    $githubConfigured = @($domains.values).Count -gt 0
    $processPat = $env:GITHUB_PAT
    if (-not $githubConfigured -and -not [string]::IsNullOrWhiteSpace($processPat)) {
        Invoke-DataPlanePut -Path '/api/v2/github/domains/github_com' -Body @{
            AuthType = 'Pat'
            Pat = $processPat
        }
        $processPat = $null
        $githubConfigured = $true
    }

    if (-not $githubConfigured) {
        $oauthConfig = Invoke-RestMethod -Uri "$agentEndpoint/api/v2/github/oauth/config" -Method Get -Headers $headers
        $oauthUrl = if ($oauthConfig.PSObject.Properties.Name -contains 'oAuthUrl') {
            $oauthConfig.oAuthUrl
        }
        elseif ($oauthConfig.PSObject.Properties.Name -contains 'OAuthUrl') {
            $oauthConfig.OAuthUrl
        }
        else {
            $null
        }
        if ([string]::IsNullOrWhiteSpace($oauthUrl)) {
            throw 'GitHub OAuth is not configured and the SRE Agent did not return an authorization URL.'
        }
        Write-Warning "Complete GitHub OAuth interactively, then rerun this script: $oauthUrl"
    }
    else {
        $repositoryDefinition = Get-Content (Join-Path $configRoot 'repository.json') -Raw | ConvertFrom-Json
        Invoke-DataPlanePut -Path '/api/v2/repos/grifols-sre-agent-demo' -Body $repositoryDefinition
    }

    $subagentDefinition = Get-Content (Join-Path $configRoot 'code-analyzer.json') -Raw | ConvertFrom-Json
    Invoke-DataPlanePut -Path '/api/v2/extendedAgent/agents/code-analyzer' -Body @{
        name = 'code-analyzer'
        type = 'ExtendedAgent'
        tags = @('synthetic', 'cold-chain')
        owner = ''
        properties = @{
            instructions = ($subagentDefinition.instructions -join "`n")
            handoffDescription = $subagentDefinition.description
            handoffs = @()
            tools = @(
                'SearchMemory',
                'RunAzCliReadCommands',
                'QueryLogAnalyticsByWorkspaceId',
                'QueryAppInsightsByResourceId',
                'FindConnectedGitHubRepo',
                'GetIaCForGitHub'
            )
            mcpTools = @()
            allowParallelToolCalls = $true
            enableSkills = $true
        }
    }

    $incidentFilterDefinition = Get-Content (Join-Path $configRoot 'cold-chain-sev2-review.json') -Raw |
        ConvertFrom-Json
    $incidentFilterDefinition.properties.azMonitorFilterSettings.targetResource =
        "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.App/containerApps/$BackendAppName"
    Invoke-DataPlanePut -Path '/api/v2/extendedAgent/incidentFilters/cold-chain-sev2-review' -Body $incidentFilterDefinition

    $null = Invoke-RestMethod -Uri "$agentEndpoint/api/v2/extendedAgent/agents/code-analyzer" -Method Get -Headers $headers
    $null = Invoke-RestMethod -Uri "$agentEndpoint/api/v2/extendedAgent/incidentFilters/cold-chain-sev2-review" -Method Get -Headers $headers
    if ($githubConfigured) {
        $null = Invoke-RestMethod -Uri "$agentEndpoint/api/v2/repos/grifols-sre-agent-demo" -Method Get -Headers $headers
    }
    $configuredLimit = az rest `
        --method Get `
        --url "$agentBase?api-version=2026-01-01" `
        --query properties.monthlyAgentUnitLimit `
        --output tsv
    if ([int]$configuredLimit -ne $MonthlyAgentUnitLimit) {
        throw "Expected monthly agent unit limit $MonthlyAgentUnitLimit, found $configuredLimit."
    }
}
finally {
    $processPat = $null
    $headers.Authorization = $null
    $token = $null
}

Write-Host 'SRE Agent observability, subagent, Sev2 Review response handling, and monthly unit limit verified.'
