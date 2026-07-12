#requires -Version 7.2
[CmdletBinding()]
param(
    [string] $SubscriptionId = '5305e853-a63b-4b82-9a3f-6fde18c1a798',
    [string] $ResourceGroupName = 'rg-demo-sre-agent-v1',
    [string] $AgentName = 'sre-agent-grifols-v1',
    [string] $RepositoryUrl = 'https://github.com/marioaguileraaa/grifols-sre-agent-demo',
    [string] $RepositoryName = 'grifols-sre-agent-demo',
    [string] $GitHubRepository = 'marioaguileraaa/grifols-sre-agent-demo',
    [string] $BridgeName = 'logic-grifols-sre-trigger-v1',
    [string] $BridgeLocation = 'eastus2',
    [ValidateRange(500, 1000000)]
    [int] $MonthlyAgentUnitLimit = 1000,
    [switch] $SetGitHubSecret
)

. "$PSScriptRoot\AzureDemo.Common.ps1"

$sreAdministratorRoleId = 'e79298df-d852-4c6d-84f9-5d13249d1e55'
$sreStandardUserRoleId = '2d84a65a-63b2-4343-bbb6-31105d857bc1'
$previewApiVersion = '2025-05-01-preview'
$logicAppApiVersion = '2019-05-01'
$deploymentApiVersion = '2022-09-01'
$triggerName = 'grifols-controlled-issue'
$agentResourceId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.App/agents/$AgentName"
$agentArmUrl = "https://management.azure.com${agentResourceId}"
$bridgeArmUrl = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Logic/workflows/$BridgeName"
$bridgeTemplateFile = Join-Path $PSScriptRoot '..\infra\trigger-bridge.bicep'

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
$script:agentHttpClient = $null

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

    if ($null -eq $script:agentHttpClient) {
        $handler = [System.Net.Http.HttpClientHandler]::new()
        $handler.AllowAutoRedirect = $false
        $script:agentHttpClient = [System.Net.Http.HttpClient]::new($handler, $true)
    }

    $request = [System.Net.Http.HttpRequestMessage]::new(
        [System.Net.Http.HttpMethod]::new($Method.ToUpperInvariant()),
        "$endpoint$Path"
    )
    $response = $null
    try {
        foreach ($header in $script:dataPlaneHeaders.GetEnumerator()) {
            if ($header.Key -eq 'Content-Type') {
                continue
            }
            if (-not $request.Headers.TryAddWithoutValidation([string] $header.Key, [string] $header.Value)) {
                throw "Unable to add SRE Agent API request header '$($header.Key)'."
            }
        }
        if ($null -ne $Body) {
            $jsonBody = $Body | ConvertTo-Json -Depth 30
            $request.Content = [System.Net.Http.StringContent]::new(
                $jsonBody,
                [System.Text.Encoding]::UTF8,
                'application/json'
            )
        }

        $response = $script:agentHttpClient.Send($request)
        $response.EnsureSuccessStatusCode() | Out-Null
        if ($null -eq $response.Content) {
            return $null
        }
        $responseBody = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        if ([string]::IsNullOrWhiteSpace($responseBody)) {
            return $null
        }
        return $responseBody | ConvertFrom-Json
    } finally {
        if ($null -ne $response) {
            $response.Dispose()
        }
        $request.Dispose()
    }
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
    $oauthUrl = Get-OptionalPropertyValue -InputObject $oauth -PropertyName 'oAuthUrl'
    $oauthUri = $null
    if ([string]::IsNullOrWhiteSpace($oauthUrl) -or
        -not [System.Uri]::TryCreate($oauthUrl, [System.UriKind]::Absolute, [ref] $oauthUri)) {
        throw 'INCOMPLETE: GitHub authentication is required, but the SRE Agent did not provide a valid interactive OAuth destination.'
    }
    $oauthDestinationAllowed = $oauthUri.Scheme -eq 'https' -and
        $oauthUri.Host -eq 'github.com' -and
        $oauthUri.IsDefaultPort -and
        [string]::IsNullOrEmpty($oauthUri.UserInfo) -and
        $oauthUri.AbsolutePath.StartsWith('/login/oauth/', [System.StringComparison]::OrdinalIgnoreCase)
    if (-not $oauthDestinationAllowed) {
        throw 'INCOMPLETE: GitHub authentication is required, but the interactive OAuth destination was not an approved GitHub HTTPS authorization path.'
    }
    try {
        Start-Process $oauthUri.AbsoluteUri
    } catch {
        throw 'INCOMPLETE: GitHub authentication is required, but the interactive OAuth flow could not be opened securely.'
    }
    Write-Host 'INCOMPLETE: GitHub authentication is required before source indexing.'
    Write-Host 'Complete the OAuth flow opened in the browser, then rerun this script.'
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
$repositoriesResponse = Invoke-AgentApi -Method Get -Path '/api/v2/repos' -Body $null
$repositories = Get-ResponseItems -Response $repositoriesResponse -PropertyNames @('value', 'values', 'repos', 'repositories', 'items')
$existingRepository = $repositories | Where-Object {
    $candidateProperties = Get-OptionalPropertyValue -InputObject $_ -PropertyName 'properties'
    $candidateName = @(
        Get-OptionalPropertyValue -InputObject $_ -PropertyName 'name'
        Get-OptionalPropertyValue -InputObject $candidateProperties -PropertyName 'name'
    ) | Where-Object { $null -ne $_ } | Select-Object -First 1
    $candidateName -eq $RepositoryName
} | Select-Object -First 1

if ($null -ne $existingRepository) {
    $existingRepository = Invoke-AgentApi -Method Get -Path "/api/v2/repos/$RepositoryName" -Body $null
}
$existingRepositoryProperties = Get-OptionalPropertyValue -InputObject $existingRepository -PropertyName 'properties'
$existingRepositoryUrl = @(
    Get-OptionalPropertyValue -InputObject $existingRepositoryProperties -PropertyName 'url'
    Get-OptionalPropertyValue -InputObject $existingRepository -PropertyName 'url'
) | Where-Object { $null -ne $_ } | Select-Object -First 1
$existingRepositoryBranch = @(
    Get-OptionalPropertyValue -InputObject $existingRepositoryProperties -PropertyName 'branch'
    Get-OptionalPropertyValue -InputObject $existingRepository -PropertyName 'branch'
) | Where-Object { $null -ne $_ } | Select-Object -First 1
$existingRepositoryType = @(
    Get-OptionalPropertyValue -InputObject $existingRepositoryProperties -PropertyName 'type'
    Get-OptionalPropertyValue -InputObject $existingRepository -PropertyName 'type'
) | Where-Object { $null -ne $_ } | Select-Object -First 1
$existingCloneStatus = @(
    Get-OptionalPropertyValue -InputObject $existingRepositoryProperties -PropertyName 'cloneStatus'
    Get-OptionalPropertyValue -InputObject $existingRepository -PropertyName 'cloneStatus'
) | Where-Object { $null -ne $_ } | Select-Object -First 1
$existingRepositoryBranchMatchesDesired = [string]::IsNullOrWhiteSpace($existingRepositoryBranch) `
    -or $existingRepositoryBranch -eq 'main'
$repositoryMatchesDesired = $null -ne $existingRepository `
    -and $existingRepositoryUrl -eq $RepositoryUrl `
    -and $existingRepositoryBranchMatchesDesired `
    -and $existingRepositoryType -eq 'GitHub'

if ($null -eq $existingRepository) {
    Invoke-AgentApi -Method Put -Path "/api/v2/repos/$RepositoryName" -Body $repositoryBody | Out-Null
    Write-Host "Created repository '$RepositoryName'."
} elseif (-not $repositoryMatchesDesired) {
    throw "Repository '$RepositoryName' already exists with a different URL, type, or branch. Refusing destructive replacement."
} elseif ($existingCloneStatus -eq 'Ready') {
    Write-Host "Reusing existing Ready repository '$RepositoryName'."
} else {
    Write-Host "Repository '$RepositoryName' already has the desired source configuration; waiting for cloneStatus '$existingCloneStatus' to complete."
}

$repoDeadline = (Get-Date).AddMinutes(10)
$cloneStatus = $null
do {
    $repoStatus = Invoke-AgentApi -Method Get -Path "/api/v2/repos/$RepositoryName" -Body $null
    $repoStatusProperties = Get-OptionalPropertyValue -InputObject $repoStatus -PropertyName 'properties'
    $cloneStatus = @(
        Get-OptionalPropertyValue -InputObject $repoStatusProperties -PropertyName 'cloneStatus'
        Get-OptionalPropertyValue -InputObject $repoStatus -PropertyName 'cloneStatus'
    ) | Where-Object { $null -ne $_ } | Select-Object -First 1
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
$verifiedRepoProperties = Get-OptionalPropertyValue -InputObject $verifiedRepo -PropertyName 'properties'
$verifiedCloneStatus = @(
    Get-OptionalPropertyValue -InputObject $verifiedRepoProperties -PropertyName 'cloneStatus'
    Get-OptionalPropertyValue -InputObject $verifiedRepo -PropertyName 'cloneStatus'
) | Where-Object { $null -ne $_ } | Select-Object -First 1
if ($verifiedCloneStatus -ne 'Ready') {
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

$bridgeDeploymentDeadline = (Get-Date).AddMinutes(10)
$bridgeDeploymentSucceeded = $false
$bridgeTemplateJson = az bicep build `
    --file $bridgeTemplateFile `
    --stdout 2>$null
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($bridgeTemplateJson)) {
    throw 'Unable to compile the authenticated SRE trigger bridge template.'
}
try {
    $bridgeTemplate = $bridgeTemplateJson | ConvertFrom-Json
} catch {
    throw 'The compiled SRE trigger bridge template was not valid JSON.'
}

$armAccessToken = az account get-access-token `
    --resource 'https://management.azure.com/' `
    --query accessToken `
    --output tsv 2>$null
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($armAccessToken)) {
    throw 'Unable to acquire an Azure Resource Manager token for the bridge deployment.'
}
$bridgeDeploymentUrl = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Resources/deployments/sre-trigger-bridge?api-version=$deploymentApiVersion"
$bridgeDeploymentBody = @{
    properties = @{
        mode = 'Incremental'
        template = $bridgeTemplate
        parameters = @{
            agentName = @{ value = $AgentName }
            bridgeName = @{ value = $BridgeName }
            bridgeLocation = @{ value = $BridgeLocation }
            protectedTriggerUrl = @{ value = $triggerUrl }
        }
    }
} | ConvertTo-Json -Depth 100 -Compress
$armHeaders = @{
    Authorization = "Bearer $armAccessToken"
}

do {
    $deploymentAccepted = $false
    try {
        Invoke-RestMethod `
            -Method Put `
            -Uri $bridgeDeploymentUrl `
            -Headers $armHeaders `
            -ContentType 'application/json' `
            -Body $bridgeDeploymentBody `
            -SkipHttpErrorCheck `
            -StatusCodeVariable deploymentStatus | Out-Null
        $deploymentAccepted = $deploymentStatus -in @(200, 201, 202)
    } catch {
        $deploymentAccepted = $false
    }

    if ($deploymentAccepted) {
        do {
            $deploymentState = $null
            try {
                $deployment = Invoke-RestMethod `
                    -Method Get `
                    -Uri $bridgeDeploymentUrl `
                    -Headers $armHeaders `
                    -SkipHttpErrorCheck `
                    -StatusCodeVariable deploymentStatus
                if ($deploymentStatus -eq 200) {
                    $deploymentState = $deployment.properties.provisioningState
                }
            } catch {
                $deploymentState = $null
            }

            if ($deploymentState -eq 'Succeeded') {
                $bridgeDeploymentSucceeded = $true
                break
            }
            if ($deploymentState -in @('Failed', 'Canceled')) {
                break
            }
            Start-Sleep -Seconds 10
        } while ((Get-Date) -lt $bridgeDeploymentDeadline)
    }

    if ($bridgeDeploymentSucceeded) {
        break
    }
    Start-Sleep -Seconds 15
} while ((Get-Date) -lt $bridgeDeploymentDeadline)
$armHeaders.Clear()
$armAccessToken = $null
$bridgeDeploymentBody = $null
$bridgeTemplateJson = $null
if (-not $bridgeDeploymentSucceeded) {
    throw 'Unable to deploy the authenticated SRE trigger bridge within ten minutes. No protected URL was printed.'
}

$bridge = az rest `
    --method get `
    --url "${bridgeArmUrl}?api-version=$logicAppApiVersion" `
    --only-show-errors `
    --output json 2>$null | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or
    $bridge.properties.provisioningState -ne 'Succeeded' -or
    $bridge.properties.state -ne 'Enabled' -or
    -not [string]::Equals($bridge.location, $BridgeLocation, [System.StringComparison]::OrdinalIgnoreCase) -or
    $bridge.identity.type -ne 'SystemAssigned' -or
    [string]::IsNullOrWhiteSpace($bridge.identity.principalId)) {
    throw 'Logic App bridge provisioning or system-assigned identity verification failed.'
}

$bridgePrincipalId = [string] $bridge.identity.principalId
$roleAssignmentDeadline = (Get-Date).AddMinutes(10)
$bridgeRoleAssignment = $null
do {
    $bridgeRoleAssignments = az role assignment list `
        --subscription $SubscriptionId `
        --assignee-object-id $bridgePrincipalId `
        --scope $agentResourceId `
        --fill-principal-name false `
        --only-show-errors `
        --output json 2>$null | ConvertFrom-Json
    if ($LASTEXITCODE -eq 0) {
        $bridgeRoleAssignment = $bridgeRoleAssignments | Where-Object {
            [string]::Equals($_.scope, $agentResourceId, [System.StringComparison]::OrdinalIgnoreCase) -and
            $_.roleDefinitionId -match "/$sreStandardUserRoleId$"
        } | Select-Object -First 1
    }
    if ($null -ne $bridgeRoleAssignment) {
        break
    }
    Start-Sleep -Seconds 15
} while ((Get-Date) -lt $roleAssignmentDeadline)
if ($null -eq $bridgeRoleAssignment) {
    throw 'The Logic App bridge did not receive SRE Agent Standard User at the exact agent resource scope within ten minutes.'
}

$allBridgeRoleAssignments = az role assignment list `
    --subscription $SubscriptionId `
    --assignee-object-id $bridgePrincipalId `
    --all `
    --fill-principal-name false `
    --only-show-errors `
    --output json 2>$null | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to verify that the Logic App bridge identity has no additional role assignments.'
}
$expectedBridgeRoleAssignments = @($allBridgeRoleAssignments | Where-Object {
    [string]::Equals($_.scope, $agentResourceId, [System.StringComparison]::OrdinalIgnoreCase) -and
    $_.roleDefinitionId -match "/$sreStandardUserRoleId$"
})
if ($expectedBridgeRoleAssignments.Count -ne 1) {
    throw 'The Logic App bridge identity must have exactly one SRE Agent Standard User assignment at the agent resource scope.'
}
$unexpectedBridgeRoleAssignments = $allBridgeRoleAssignments | Where-Object {
    -not (
        [string]::Equals($_.scope, $agentResourceId, [System.StringComparison]::OrdinalIgnoreCase) -and
        $_.roleDefinitionId -match "/$sreStandardUserRoleId$"
    )
}
if ($null -ne $unexpectedBridgeRoleAssignments) {
    throw 'The Logic App bridge identity has an unexpected role assignment. Keep only SRE Agent Standard User at the exact agent resource scope.'
}

if (-not $SetGitHubSecret) {
    throw 'INCOMPLETE: SRE_TRIGGER_URL was not set. Rerun with -SetGitHubSecret so only the authenticated bridge callback is piped securely to GitHub.'
}

$callbackDeadline = (Get-Date).AddMinutes(5)
$callbackUrl = $null
do {
    $callbackUrl = az rest `
        --method post `
        --url "${bridgeArmUrl}/triggers/manual/listCallbackUrl?api-version=$logicAppApiVersion" `
        --query value `
        --only-show-errors `
        --output tsv 2>$null
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($callbackUrl)) {
        break
    }
    $callbackUrl = $null
    Start-Sleep -Seconds 10
} while ((Get-Date) -lt $callbackDeadline)
if ([string]::IsNullOrWhiteSpace($callbackUrl)) {
    throw 'Unable to obtain the Logic App Request callback without exposing its signature.'
}
$callbackUri = $null
if (-not [System.Uri]::TryCreate($callbackUrl.Trim(), [System.UriKind]::Absolute, [ref] $callbackUri) -or
    $callbackUri.Scheme -ne 'https' -or
    [string]::IsNullOrWhiteSpace($callbackUri.Query) -or
    $callbackUri.Query -notmatch '(^\?|&)sig=') {
    throw 'The Logic App Request callback was not a valid signed HTTPS URL.'
}
$callbackUrl = $callbackUri.AbsoluteUri

$callbackUrl | gh secret set SRE_TRIGGER_URL --repo $GitHubRepository
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to set GitHub secret SRE_TRIGGER_URL to the authenticated bridge callback.'
}
Write-Host "GitHub secret SRE_TRIGGER_URL set for $GitHubRepository without printing the callback or protected trigger URL."

Write-Host "SRE Agent configuration verified: repo=Ready, connectors=UAMI, incident=AzMonitor, mode=Review, access=Low, monthlyLimit=$MonthlyAgentUnitLimit."
