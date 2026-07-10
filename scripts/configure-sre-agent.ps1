#requires -Version 7.2
[CmdletBinding()]
param(
    [string] $SubscriptionId = '5305e853-a63b-4b82-9a3f-6fde18c1a798',
    [string] $ResourceGroupName = 'rg-demo-sre-agent-v1',
    [string] $AgentName = 'sre-agent-grifols-v1',
    [string] $RepositoryUrl = 'https://github.com/marioaguileraaa/grifols-sre-agent-demo',
    [string] $RepositoryName = 'grifols-sre-agent-demo',
    [string] $GitHubRepository = 'marioaguileraaa/grifols-sre-agent-demo',
    [ValidateRange(500, 1000000)]
    [int] $MonthlyAgentUnitLimit = 1000,
    [switch] $SetGitHubSecret
)

. "$PSScriptRoot\AzureDemo.Common.ps1"

$sreAdministratorRoleId = 'e79298df-d852-4c6d-84f9-5d13249d1e55'
$previewApiVersion = '2025-05-01-preview'
$triggerName = 'grifols-controlled-issue'
$agentResourceId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.App/agents/$AgentName"
$agentArmUrl = "https://management.azure.com${agentResourceId}"

Assert-DemoAzureContext -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName

$signedInUserId = az ad signed-in-user show --query id --output tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($signedInUserId)) {
    throw 'A signed-in Azure user is required to configure the SRE Agent data plane.'
}

$existingAdminAssignments = az role assignment list `
    --assignee-object-id $signedInUserId `
    --scope $agentResourceId `
    --fill-principal-name false `
    --output json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to inspect SRE Agent Administrator assignments.'
}

$hasAdministratorRole = $existingAdminAssignments | Where-Object {
    $_.roleDefinitionId -match "/$sreAdministratorRoleId$"
}
if (-not $hasAdministratorRole) {
    az role assignment create `
        --assignee-object-id $signedInUserId `
        --assignee-principal-type User `
        --role $sreAdministratorRoleId `
        --scope $agentResourceId `
        --output none
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to grant the signed-in user SRE Agent Administrator at agent scope.'
    }
    Write-Host 'Granted the signed-in user SRE Agent Administrator at agent scope.'
} else {
    Write-Host 'Signed-in user already has SRE Agent Administrator at agent scope.'
}

$limitPatch = @{
    properties = @{
        monthlyAgentUnitLimit = $MonthlyAgentUnitLimit
    }
} | ConvertTo-Json -Depth 4 -Compress
az rest `
    --method patch `
    --url "${agentArmUrl}?api-version=$previewApiVersion" `
    --headers 'Content-Type=application/json' `
    --body $limitPatch `
    --output none
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to configure monthlyAgentUnitLimit through the control plane.'
}

$agent = az rest `
    --method get `
    --url "${agentArmUrl}?api-version=$previewApiVersion" `
    --output json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($agent.properties.agentEndpoint)) {
    throw 'The SRE Agent ARM resource did not expose an agentEndpoint.'
}

$endpoint = $agent.properties.agentEndpoint.TrimEnd('/')
$script:dataPlaneHeaders = $null

function Get-ResponseItems {
    param(
        [object] $Response,
        [string[]] $PropertyNames
    )

    if ($null -eq $Response) {
        return @()
    }
    if ($Response -is [array]) {
        return @($Response)
    }
    foreach ($propertyName in $PropertyNames) {
        $property = $Response.PSObject.Properties[$propertyName]
        if ($null -ne $property -and $null -ne $property.Value) {
            return @($property.Value)
        }
    }
    return @($Response)
}

function Get-OptionalPropertyValue {
    param(
        [AllowNull()]
        [object] $InputObject,
        [Parameter(Mandatory)]
        [string] $PropertyName
    )

    if ($null -eq $InputObject) {
        return $null
    }
    $property = $InputObject.PSObject.Properties[$PropertyName]
    if ($null -eq $property) {
        return $null
    }
    return $property.Value
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
        Headers = $script:dataPlaneHeaders
    }
    if ($null -ne $Body) {
        $parameters.ContentType = 'application/json'
        $parameters.Body = $Body | ConvertTo-Json -Depth 30
    }
    Invoke-RestMethod @parameters
}

$dataPlaneDeadline = (Get-Date).AddMinutes(10)
$lastDataPlaneError = $null
do {
    try {
        $accessToken = az account get-access-token `
            --resource 'https://azuresre.dev' `
            --query accessToken `
            --output tsv
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($accessToken)) {
            throw 'Unable to acquire an Azure SRE Agent data-plane token.'
        }
        $script:dataPlaneHeaders = @{
            Authorization = "Bearer $accessToken"
            'Content-Type' = 'application/json'
        }
        Invoke-AgentApi -Method Get -Path '/api/v2/repos' -Body $null | Out-Null
        $lastDataPlaneError = $null
        break
    } catch {
        $lastDataPlaneError = $_
        Start-Sleep -Seconds 15
    }
} while ((Get-Date) -lt $dataPlaneDeadline)

if ($null -ne $lastDataPlaneError) {
    throw "SRE Agent Administrator propagation did not complete within ten minutes: $($lastDataPlaneError.Exception.Message)"
}

$domainsResponse = Invoke-AgentApi -Method Get -Path '/api/v2/github/domains' -Body $null
$domains = Get-ResponseItems -Response $domainsResponse -PropertyNames @('value', 'values', 'domains', 'items')
$githubDomain = $domains | Where-Object {
    $domainProperties = Get-OptionalPropertyValue -InputObject $_ -PropertyName 'properties'
    $domainName = @(
        Get-OptionalPropertyValue -InputObject $_ -PropertyName 'name'
        Get-OptionalPropertyValue -InputObject $_ -PropertyName 'domain'
        Get-OptionalPropertyValue -InputObject $domainProperties -PropertyName 'domain'
    ) | Where-Object { $null -ne $_ } | Select-Object -First 1
    $domainName -in @('github_com', 'github.com')
} | Select-Object -First 1
$githubDomainProperties = Get-OptionalPropertyValue -InputObject $githubDomain -PropertyName 'properties'
$githubDomainStatus = @(
    Get-OptionalPropertyValue -InputObject $githubDomainProperties -PropertyName 'status'
    Get-OptionalPropertyValue -InputObject $githubDomainProperties -PropertyName 'connectionStatus'
    Get-OptionalPropertyValue -InputObject $githubDomain -PropertyName 'status'
    Get-OptionalPropertyValue -InputObject $githubDomain -PropertyName 'connectionStatus'
) | Where-Object { $null -ne $_ } | Select-Object -First 1
$githubDomainIsHealthy = Get-OptionalPropertyValue -InputObject $githubDomain -PropertyName 'isHealthy'
$domainReady = if ($null -ne $githubDomainIsHealthy) {
    $githubDomainIsHealthy -eq $true
} else {
    $null -ne $githubDomain -and $githubDomainStatus -in @('Connected', 'Ready', 'Authenticated', 'Succeeded')
}

if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_PAT)) {
    Invoke-AgentApi -Method Put -Path '/api/v2/github/domains/github_com' -Body @{
        AuthType = 'Pat'
        Pat = $env:GITHUB_PAT
    } | Out-Null
    Write-Host 'GitHub PAT submitted to Azure SRE Agent secure domain storage; it was not printed or written to repository/disk.'
    $domainReady = $true
} elseif (-not $domainReady) {
    $oauth = Invoke-AgentApi -Method Get -Path '/api/v2/github/oauth/config' -Body $null
    Write-Host 'INCOMPLETE: GitHub authentication is required before source indexing.'
    Write-Host 'Complete OAuth in a browser, then rerun this script:'
    Write-Host $oauth.oAuthUrl
    throw 'INCOMPLETE: no authenticated GitHub domain or GITHUB_PAT was available.'
} else {
    Write-Host "Using existing authenticated GitHub domain. Status=$githubDomainStatus"
}

$repositoryBody = @{
    name = $RepositoryName
    type = 'CodeRepo'
    properties = @{
        url = $RepositoryUrl
        type = 'GitHub'
        branch = 'main'
        description = 'Synthetic Grifols Plasma Supply SRE demo source'
    }
}
Invoke-AgentApi -Method Put -Path "/api/v2/repos/$RepositoryName" -Body $repositoryBody | Out-Null

$repoDeadline = (Get-Date).AddMinutes(10)
do {
    $repoStatus = Invoke-AgentApi -Method Get -Path "/api/v2/repos/$RepositoryName" -Body $null
    $cloneStatus = $repoStatus.properties.cloneStatus ?? $repoStatus.cloneStatus
    if ($cloneStatus -eq 'Ready') {
        break
    }
    if ($cloneStatus -in @('Failed', 'Error', 'Canceled')) {
        throw "Repository indexing failed with cloneStatus '$cloneStatus'."
    }
    Start-Sleep -Seconds 10
} while ((Get-Date) -lt $repoDeadline)
if ($cloneStatus -ne 'Ready') {
    throw "Repository cloneStatus did not reach Ready within ten minutes. Last status: '$cloneStatus'."
}

foreach ($connectorName in @('log-analytics', 'application-insights')) {
    $connector = az rest `
        --method get `
        --url "${agentArmUrl}/connectors/${connectorName}?api-version=$previewApiVersion" `
        --output json | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to read ARM connector '$connectorName'."
    }
    if ($connector.properties.identity -ne $agent.properties.actionConfiguration.identity) {
        throw "ARM connector '$connectorName' is not using the SRE UAMI."
    }
    if ($connector.properties.provisioningState -notin @('Succeeded', $null)) {
        throw "ARM connector '$connectorName' provisioning state is '$($connector.properties.provisioningState)'."
    }
}

$codeAnalyzer = @{
    name = 'code-analyzer'
    type = 'ExtendedAgent'
    tags = @('grifols-demo', 'synthetic-data')
    owner = ''
    properties = @{
        instructions = @'
Investigate only the fictional Grifols Plasma Supply demo. Correlate Azure Container Apps 5xx telemetry with structured logs by correlation ID, requisition ID, distribution center, error code, and RootCauseClue. Inspect the connected main branch and cite file:line evidence. Treat all data as synthetic. In Review mode, propose the reversible mitigation of setting DEMO_COLD_CHAIN_FAILURE_RATE to 0; never execute a write without explicit approval.
'@
        handoffDescription = 'Correlate Azure Monitor telemetry and repository source for the fictional cold-chain 5xx demo.'
        handoffs = @()
        tools = @(
            'SearchMemory',
            'RunAzCliReadCommands',
            'RunAzCliWriteCommands',
            'GetAzCliHelp',
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

$triggerPayload = @{
    name = $triggerName
    description = 'Investigate a controlled synthetic incident from GitHub.'
    agentPrompt = 'Analyze the supplied synthetic incident using Azure Monitor telemetry and the connected repository. Return evidence and a Review-mode mitigation proposal.'
    agent = 'code-analyzer'
    agentMode = 'Review'
}
$triggerListResponse = Invoke-AgentApi -Method Get -Path '/api/v1/httptriggers' -Body $null
$triggers = Get-ResponseItems -Response $triggerListResponse -PropertyNames @('value', 'values', 'triggers', 'items')
$existingTrigger = $triggers | Where-Object {
    ($_.name ?? $_.properties.name) -eq $triggerName
} | Select-Object -First 1

if ($null -ne $existingTrigger) {
    $triggerId = $existingTrigger.id ?? $existingTrigger.triggerId ?? $existingTrigger.properties.id
    if ([string]::IsNullOrWhiteSpace($triggerId)) {
        throw 'Existing HTTP trigger did not expose an ID.'
    }
    $triggerPayload['id'] = $triggerId
    $trigger = Invoke-AgentApi -Method Put -Path "/api/v1/httptriggers/$triggerId" -Body $triggerPayload
} else {
    $trigger = Invoke-AgentApi -Method Post -Path '/api/v1/httptriggers/create' -Body $triggerPayload
    $triggerId = $trigger.id ?? $trigger.triggerId ?? $trigger.properties.id
}
if ([string]::IsNullOrWhiteSpace($triggerId)) {
    throw 'HTTP trigger configuration did not return an ID.'
}

$triggerUrl = $trigger.triggerUrl `
    ?? $trigger.webhookUrl `
    ?? $existingTrigger.triggerUrl `
    ?? $existingTrigger.webhookUrl `
    ?? "$endpoint/api/v1/httptriggers/trigger/$triggerId"

if ($SetGitHubSecret) {
    $triggerUrl | gh secret set SRE_TRIGGER_URL --repo $GitHubRepository
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to set GitHub secret SRE_TRIGGER_URL.'
    }
    Write-Host "GitHub secret SRE_TRIGGER_URL set for $GitHubRepository without printing the URL."
} else {
    throw 'INCOMPLETE: SRE_TRIGGER_URL was not set. Rerun with -SetGitHubSecret so the trigger URL is piped securely to GitHub without being printed.'
}

$verifiedAgent = az rest `
    --method get `
    --url "${agentArmUrl}?api-version=$previewApiVersion" `
    --output json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to verify final agent ARM configuration.'
}
if ($verifiedAgent.properties.incidentManagementConfiguration.type -ne 'AzMonitor') {
    throw 'Agent incidentManagementConfiguration is not AzMonitor.'
}
if ($verifiedAgent.properties.actionConfiguration.mode -ne 'Review' -or
    $verifiedAgent.properties.actionConfiguration.accessLevel -ne 'Low') {
    throw 'Agent must remain Review/Low.'
}
if ([int]$verifiedAgent.properties.monthlyAgentUnitLimit -ne $MonthlyAgentUnitLimit) {
    throw "monthlyAgentUnitLimit verification failed. Expected $MonthlyAgentUnitLimit."
}

$verifiedRepo = Invoke-AgentApi -Method Get -Path "/api/v2/repos/$RepositoryName" -Body $null
if (($verifiedRepo.properties.cloneStatus ?? $verifiedRepo.cloneStatus) -ne 'Ready') {
    throw 'Repository is not Ready after configuration.'
}
$verifiedSubagent = Invoke-AgentApi -Method Get -Path '/api/v2/extendedAgent/agents/code-analyzer' -Body $null
$verifiedFilter = Invoke-AgentApi -Method Get -Path '/api/v2/extendedAgent/incidentFilters/grifols-cold-chain-sev2' -Body $null
$verifiedTriggersResponse = Invoke-AgentApi -Method Get -Path '/api/v1/httptriggers' -Body $null
$verifiedTriggers = Get-ResponseItems -Response $verifiedTriggersResponse -PropertyNames @('value', 'values', 'triggers', 'items')
$verifiedTrigger = $verifiedTriggers | Where-Object {
    ($_.id ?? $_.triggerId ?? $_.properties.id) -eq $triggerId
} | Select-Object -First 1
if ($null -eq $verifiedSubagent -or $null -eq $verifiedFilter -or $null -eq $verifiedTrigger) {
    throw 'Subagent, response plan, or HTTP trigger verification failed.'
}
$verifiedFilterMode = $verifiedFilter.properties.agentMode ?? $verifiedFilter.agentMode
if ($verifiedFilterMode -ne 'Review') {
    throw "Incident filter must remain in Review mode. Reported: '$verifiedFilterMode'."
}
$verifiedTriggerMode = $verifiedTrigger.agentMode ?? $verifiedTrigger.properties.agentMode
$verifiedTriggerAgent = $verifiedTrigger.agent ?? $verifiedTrigger.properties.agent
$verifiedTriggerPrompt = $verifiedTrigger.agentPrompt ?? $verifiedTrigger.properties.agentPrompt
if ($verifiedTriggerMode -ne 'Review' -or
    $verifiedTriggerAgent -ne 'code-analyzer' -or
    [string]::IsNullOrWhiteSpace($verifiedTriggerPrompt)) {
    throw 'HTTP trigger did not preserve agentMode=Review, agent=code-analyzer, and agentPrompt.'
}

Write-Host "SRE Agent configuration verified: repo=Ready, connectors=UAMI, incident=AzMonitor, mode=Review, access=Low, monthlyLimit=$MonthlyAgentUnitLimit."
