#requires -Version 7.2
[CmdletBinding()]
param(
    [string] $SubscriptionId = '5305e853-a63b-4b82-9a3f-6fde18c1a798',
    [string] $ResourceGroupName = 'rg-demo-sre-agent-v1',
    [string] $AgentName = 'sre-agent-grifols-v1',
    [string] $RepositoryUrl = 'https://github.com/marioaguileraaa/grifols-sre-agent-demo',
    [string] $RepositoryName = 'grifols-sre-agent-demo',
    [switch] $EnableGitHubWrite
)

. "$PSScriptRoot\AzureDemo.Common.ps1"

Assert-DemoAzureContext -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName
$agentResourceId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.App/agents/$AgentName"
$agent = az rest `
    --method get `
    --url "https://management.azure.com${agentResourceId}?api-version=2026-01-01" `
    --output json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($agent.properties.agentEndpoint)) {
    throw 'The SRE Agent ARM resource exists but did not expose an agentEndpoint.'
}

$accessToken = az account get-access-token `
    --resource 'https://azuresre.dev' `
    --query accessToken `
    --output tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($accessToken)) {
    throw 'Unable to acquire an Azure SRE Agent data-plane token. Run: az login --scope https://azuresre.dev/.default'
}

$endpoint = $agent.properties.agentEndpoint.TrimEnd('/')
$headers = @{
    Authorization = "Bearer $accessToken"
    'Content-Type' = 'application/json'
}

function Invoke-AgentApi {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Get', 'Post', 'Put')]
        [string] $Method,
        [Parameter(Mandatory)]
        [string] $Path,
        [object] $Body
    )

    $parameters = @{
        Method = $Method
        Uri = "$endpoint$Path"
        Headers = $headers
    }
    if ($null -ne $Body) {
        $parameters.ContentType = 'application/json'
        $parameters.Body = $Body | ConvertTo-Json -Depth 30
    }
    Invoke-RestMethod @parameters
}

$repositoryBody = @{
    name = $RepositoryName
    type = 'CodeRepo'
    properties = @{
        url = $RepositoryUrl
        type = 'GitHub'
        branch = 'main'
        description = 'Public synthetic Grifols Plasma Supply SRE demo source'
    }
}
Invoke-AgentApi -Method Put -Path "/api/v2/repos/$RepositoryName" -Body $repositoryBody | Out-Null
$repoTest = Invoke-AgentApi -Method Post -Path "/api/v2/repos/$RepositoryName/test" -Body @{}
$repoStatus = Invoke-AgentApi -Method Get -Path "/api/v2/repos/$RepositoryName" -Body $null
$cloneStatus = $repoStatus.properties.cloneStatus ?? $repoTest.cloneStatus ?? $repoTest.status
if ($cloneStatus -notin @('Succeeded', 'Success', 'Ready', 'Completed')) {
    throw "Public repository configuration did not reach a successful cloneStatus. Reported: '$cloneStatus'. No OAuth/PAT was stored."
}
Write-Host "Repository validated independently: $RepositoryUrl branch=main cloneStatus=$cloneStatus"

foreach ($connectorName in @('log-analytics', 'application-insights')) {
    $connector = az rest `
        --method get `
        --url "https://management.azure.com${agentResourceId}/connectors/${connectorName}?api-version=2025-05-01-preview" `
        --output json | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or $connector.properties.provisioningState -notin @('Succeeded', $null)) {
        throw "ARM connector '$connectorName' is not validated. ProvisioningState: '$($connector.properties.provisioningState)'."
    }
    Write-Host "ARM connector validated independently: $connectorName"
}

$codeAnalyzer = @{
    name = 'code-analyzer'
    type = 'ExtendedAgent'
    tags = @('grifols-demo', 'synthetic-data')
    owner = ''
    properties = @{
        instructions = @'
Investigate only the fictional Grifols Plasma Supply demo. Correlate Azure Container Apps 5xx telemetry with structured logs by correlation ID, requisition ID, distribution center, error code, and RootCauseClue. Inspect the connected public repository main branch and cite file:line evidence. Treat all data as synthetic. In Review mode, propose the reversible mitigation of setting DEMO_COLD_CHAIN_FAILURE_RATE to 0; never execute a write without explicit approval.
'@
        handoffDescription = 'Correlate Azure Monitor telemetry and repository source for the fictional cold-chain 5xx demo.'
        handoffs = @()
        tools = @(
            'SearchMemory',
            'RunAzCliReadCommands',
            'QueryLogAnalyticsByWorkspaceId',
            'ExecutePythonCode',
            'FindConnectedGitHubRepo'
        )
        mcpTools = @()
        allowParallelToolCalls = $true
        enableSkills = $true
    }
}
Invoke-AgentApi -Method Put -Path '/api/v2/extendedAgent/agents/code-analyzer' -Body $codeAnalyzer | Out-Null
Write-Host 'Data plane validated: code-analyzer subagent configured.'

$incidentFilter = @{
    name = 'grifols-cold-chain-sev2'
    type = 'IncidentFilter'
    tags = @('grifols-demo')
    properties = @{
        incidentPlatform = 'AzMonitor'
        isEnabled = $true
        priorities = @('Sev2')
        titleContains = 'grifols'
        handlingAgent = 'code-analyzer'
        agentMode = 'Review'
        deepInvestigationEnabled = $true
        maxAutomatedInvestigationAttempts = 3
    }
}
Invoke-AgentApi -Method Put -Path '/api/v2/extendedAgent/incidentFilters/grifols-cold-chain-sev2' -Body $incidentFilter | Out-Null
Write-Host 'Data plane validated: Sev2 Review response plan configured.'

$httpTrigger = @{
    name = 'grifols-controlled-issue'
    description = 'Investigate a controlled incident-labeled GitHub issue for the synthetic demo.'
    prompt = 'Analyze this controlled synthetic incident using Azure Monitor telemetry and the connected repository. Return evidence and a Review-mode mitigation proposal.'
    handlingAgent = 'code-analyzer'
    agentMode = 'review'
}
$trigger = Invoke-AgentApi -Method Post -Path '/api/v1/httptriggers/create' -Body $httpTrigger
if ([string]::IsNullOrWhiteSpace($trigger.triggerUrl)) {
    throw 'HTTP trigger creation did not return triggerUrl.'
}
Write-Host "HTTP trigger created. Store this value as GitHub Actions secret SRE_TRIGGER_URL: $($trigger.triggerUrl)"

if ($EnableGitHubWrite) {
    if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_PAT)) {
        Invoke-AgentApi -Method Put -Path '/api/v2/github/domains/github_com' -Body @{
            AuthType = 'Pat'
            Pat = $env:GITHUB_PAT
        } | Out-Null
        Write-Host 'GitHub write authentication configured from process environment; PAT was not persisted by this script.'
    } else {
        $oauth = Invoke-AgentApi -Method Get -Path '/api/v2/github/oauth/config' -Body $null
        Write-Host 'MANUAL OAUTH CHECKPOINT: open the following URL only if GitHub write operations are required:'
        Write-Host $oauth.oAuthUrl
        Write-Host 'Public repository read and incident investigation do not require this write boundary.'
    }
}
