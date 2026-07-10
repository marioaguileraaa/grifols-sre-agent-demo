#requires -Version 7.2
[CmdletBinding()]
param(
    [string] $SubscriptionId = '5305e853-a63b-4b82-9a3f-6fde18c1a798',
    [string] $ResourceGroupName = 'rg-demo-sre-agent-v1',
    [string] $AgentName = 'sre-agent-grifols-v1',
    [string] $RepositoryUrl = 'https://github.com/marioaguileraaa/grifols-sre-agent-demo',
    [string] $RepositoryName = 'grifols-sre-agent-demo',
    [string] $RepositoryFullName = 'marioaguileraaa/grifols-sre-agent-demo',
    [ValidateRange(1, 1000000)]
    [int] $MonthlyAgentUnitLimit = 1000,
    [switch] $SetGitHubSecret
)

. "$PSScriptRoot\AzureDemo.Common.ps1"

function Get-ObjectProperty {
    param(
        [object] $InputObject,
        [Parameter(Mandatory)]
        [string[]] $Name
    )

    if ($null -eq $InputObject) {
        return $null
    }

    foreach ($candidate in $Name) {
        $property = $InputObject.PSObject.Properties[$candidate]
        if ($null -ne $property -and $null -ne $property.Value) {
            return $property.Value
        }
    }
    return $null
}

function Get-AgentDataPlaneToken {
    $token = az account get-access-token `
        --resource 'https://azuresre.dev' `
        --query accessToken `
        --output tsv
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
        return $null
    }
    return $token
}

function Connect-AgentDataPlane {
    param(
        [Parameter(Mandatory)]
        [string] $Endpoint,
        [int] $MaxAttempts = 12,
        [int] $DelaySeconds = 10
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $token = Get-AgentDataPlaneToken
        if ([string]::IsNullOrWhiteSpace($token)) {
            if ($attempt -eq $MaxAttempts) {
                throw 'Unable to acquire an Azure SRE Agent data-plane token. Run: az login --scope https://azuresre.dev/.default'
            }
            Write-Warning "Data-plane token acquisition attempt $attempt/$MaxAttempts failed; retrying."
            Start-Sleep -Seconds $DelaySeconds
            continue
        }

        $candidateHeaders = @{
            Authorization = "Bearer $token"
            'Content-Type' = 'application/json'
        }
        $response = Invoke-WebRequest `
            -Method Get `
            -Uri "$Endpoint/api/v1/httptriggers" `
            -Headers $candidateHeaders `
            -SkipHttpErrorCheck
        if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 300) {
            $script:AgentApiHeaders = $candidateHeaders
            return
        }

        if ($response.StatusCode -notin @(401, 403)) {
            throw "Azure SRE Agent data-plane readiness check failed with HTTP $($response.StatusCode)."
        }
        if ($attempt -eq $MaxAttempts) {
            throw "SRE Agent Administrator RBAC did not propagate after $MaxAttempts attempts. Last HTTP status: $($response.StatusCode)."
        }

        Write-Warning "SRE Agent RBAC is not active yet (HTTP $($response.StatusCode), attempt $attempt/$MaxAttempts); retrying with a fresh token."
        Start-Sleep -Seconds $DelaySeconds
    }
}

function Invoke-AgentApi {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Get', 'Post', 'Put')]
        [string] $Method,
        [Parameter(Mandatory)]
        [string] $Path,
        [object] $Body,
        [switch] $AllowNotFound
    )

    $parameters = @{
        Method = $Method
        Uri = "$script:AgentEndpoint$Path"
        Headers = $script:AgentApiHeaders
        SkipHttpErrorCheck = $true
    }
    if ($null -ne $Body) {
        $parameters.ContentType = 'application/json'
        $parameters.Body = $Body | ConvertTo-Json -Depth 30 -Compress
    }

    $response = Invoke-WebRequest @parameters
    if ($AllowNotFound -and $response.StatusCode -eq 404) {
        return $null
    }
    if ($response.StatusCode -lt 200 -or $response.StatusCode -ge 300) {
        throw "Azure SRE Agent API $Method $Path failed with HTTP $($response.StatusCode)."
    }
    if ([string]::IsNullOrWhiteSpace($response.Content)) {
        return $null
    }
    return $response.Content | ConvertFrom-Json
}

function Get-TriggerItems {
    param([object] $TriggerList)

    $items = Get-ObjectProperty -InputObject $TriggerList -Name @('value', 'triggers', 'items')
    if ($null -ne $items) {
        return @($items)
    }
    if ($TriggerList -is [System.Array]) {
        return @($TriggerList)
    }
    return @()
}

function Find-ControlledTrigger {
    param([object[]] $Triggers)

    return $Triggers |
        Where-Object {
            (Get-ObjectProperty -InputObject $_ -Name @('name')) -eq 'grifols-controlled-issue' -or
            (Get-ObjectProperty -InputObject (Get-ObjectProperty -InputObject $_ -Name @('properties')) -Name @('name')) -eq 'grifols-controlled-issue'
        } |
        Select-Object -First 1
}

Assert-DemoAzureContext -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName
$agentResourceId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.App/agents/$AgentName"
$agentControlPlaneUrl = "https://management.azure.com${agentResourceId}"
$controlPlaneApiVersion = '2025-05-01-preview'
$sreAgentAdministratorRoleDefinitionId = 'e79298df-d852-4c6d-84f9-5d13249d1e55'

$account = az account show --output json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or $account.user.type -ne 'user') {
    throw 'configure-sre-agent.ps1 requires an interactively signed-in Azure user.'
}

$signedInUserId = az ad signed-in-user show --query id --output tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($signedInUserId)) {
    throw 'Unable to resolve the object ID of the currently signed-in Azure user.'
}

$existingAssignment = az role assignment list `
    --subscription $SubscriptionId `
    --assignee-object-id $signedInUserId `
    --role $sreAgentAdministratorRoleDefinitionId `
    --scope $agentResourceId `
    --query '[0].id' `
    --output tsv
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to inspect the signed-in user SRE Agent Administrator assignment.'
}
if ([string]::IsNullOrWhiteSpace($existingAssignment)) {
    az role assignment create `
        --subscription $SubscriptionId `
        --assignee-object-id $signedInUserId `
        --assignee-principal-type User `
        --role $sreAgentAdministratorRoleDefinitionId `
        --scope $agentResourceId `
        --output none
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to grant the signed-in user SRE Agent Administrator at the agent resource scope.'
    }
    Write-Host 'Granted the signed-in user SRE Agent Administrator at the agent resource scope.'
} else {
    Write-Host 'Signed-in user already has SRE Agent Administrator at the agent resource scope.'
}

$monthlyLimitPatch = @{
    properties = @{
        monthlyAgentUnitLimit = $MonthlyAgentUnitLimit
    }
} | ConvertTo-Json -Depth 5 -Compress
az rest `
    --method patch `
    --url "${agentControlPlaneUrl}?api-version=$controlPlaneApiVersion" `
    --headers 'Content-Type=application/json' `
    --body $monthlyLimitPatch `
    --output none
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to patch monthlyAgentUnitLimit on the Azure SRE Agent.'
}

$agent = az rest `
    --method get `
    --url "${agentControlPlaneUrl}?api-version=$controlPlaneApiVersion" `
    --output json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to read the Azure SRE Agent after applying its monthly unit limit.'
}
if ([string]::IsNullOrWhiteSpace($agent.properties.agentEndpoint)) {
    throw 'The SRE Agent ARM resource exists but did not expose an agentEndpoint.'
}
if ($agent.properties.incidentManagementConfiguration.type -ne 'AzMonitor') {
    throw "Expected incidentManagementConfiguration.type=AzMonitor, reported '$($agent.properties.incidentManagementConfiguration.type)'."
}
if ($agent.properties.actionConfiguration.mode -ne 'Review') {
    throw "Expected actionConfiguration.mode=Review, reported '$($agent.properties.actionConfiguration.mode)'."
}
if ($agent.properties.actionConfiguration.accessLevel -ne 'Low') {
    throw "Expected actionConfiguration.accessLevel=Low, reported '$($agent.properties.actionConfiguration.accessLevel)'."
}
if ([int] $agent.properties.monthlyAgentUnitLimit -ne $MonthlyAgentUnitLimit) {
    throw "Expected monthlyAgentUnitLimit=$MonthlyAgentUnitLimit, reported '$($agent.properties.monthlyAgentUnitLimit)'."
}
Write-Host "Control plane validated: AzMonitor, Review, Low, monthlyAgentUnitLimit=$MonthlyAgentUnitLimit."

$script:AgentEndpoint = $agent.properties.agentEndpoint.TrimEnd('/')
Connect-AgentDataPlane -Endpoint $script:AgentEndpoint

$githubDomain = Invoke-AgentApi -Method Get -Path '/api/v2/github/domains/github_com' -Body $null -AllowNotFound
if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_PAT)) {
    Invoke-AgentApi -Method Put -Path '/api/v2/github/domains/github_com' -Body @{
        AuthType = 'Pat'
        Pat = $env:GITHUB_PAT
    } | Out-Null
    Write-Host 'GitHub PAT was sent from the process environment and securely stored by Azure SRE Agent; it was not printed or written to repository/disk.'
} elseif ($null -eq $githubDomain) {
    $oauth = Invoke-AgentApi -Method Get -Path '/api/v2/github/oauth/config' -Body $null
    $oauthUrl = Get-ObjectProperty -InputObject $oauth -Name @('oAuthUrl', 'oauthUrl', 'authorizationUrl')
    if ([string]::IsNullOrWhiteSpace($oauthUrl)) {
        throw 'INCOMPLETE: no GitHub domain or GITHUB_PAT exists, and the agent did not return an OAuth URL.'
    }
    Write-Host 'INCOMPLETE: authenticate GitHub code access at the OAuth URL below, then rerun this script:'
    Write-Host $oauthUrl
    throw 'INCOMPLETE: GitHub OAuth authorization is required before repository configuration.'
} else {
    Write-Host 'Existing GitHub domain authentication found; no credential was changed.'
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

$cloneSucceeded = $false
for ($attempt = 1; $attempt -le 30; $attempt++) {
    $repoStatus = Invoke-AgentApi -Method Get -Path "/api/v2/repos/$RepositoryName" -Body $null
    $repoProperties = Get-ObjectProperty -InputObject $repoStatus -Name @('properties')
    $cloneStatus = Get-ObjectProperty -InputObject $repoProperties -Name @('cloneStatus', 'status')
    if ([string]::IsNullOrWhiteSpace($cloneStatus)) {
        $cloneStatus = Get-ObjectProperty -InputObject $repoStatus -Name @('cloneStatus', 'status')
    }

    if ($cloneStatus -in @('Ready', 'Succeeded', 'Success', 'Completed')) {
        $cloneSucceeded = $true
        break
    }
    if ($cloneStatus -in @('Failed', 'Error', 'CloneFailed')) {
        throw "Repository clone failed with cloneStatus '$cloneStatus'."
    }
    if ($attempt -eq 30) {
        break
    }

    Write-Host "Repository cloneStatus='$cloneStatus'; waiting for Ready ($attempt/30)."
    Start-Sleep -Seconds 10
}
if (-not $cloneSucceeded) {
    throw "Repository did not reach cloneStatus Ready/success. Last status: '$cloneStatus'."
}
Write-Host "Repository validated: $RepositoryUrl branch=main cloneStatus=$cloneStatus."

$sreIdentityResourceId = $agent.properties.actionConfiguration.identity
foreach ($connectorName in @('log-analytics', 'application-insights')) {
    $connector = az rest `
        --method get `
        --url "${agentControlPlaneUrl}/connectors/${connectorName}?api-version=2025-05-01-preview" `
        --output json | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to validate ARM connector '$connectorName'."
    }
    if ($connector.properties.provisioningState -notin @('Succeeded', $null)) {
        throw "ARM connector '$connectorName' provisioningState is '$($connector.properties.provisioningState)'."
    }
    if ($connector.properties.identity -ne $sreIdentityResourceId) {
        throw "ARM connector '$connectorName' must use the SRE UAMI resource ID."
    }
    Write-Host "ARM connector validated: $connectorName uses the SRE UAMI."
}

$codeAnalyzer = @{
    name = 'code-analyzer'
    type = 'ExtendedAgent'
    tags = @('grifols-demo', 'synthetic-data')
    owner = ''
    properties = @{
        instructions = @'
Investigate only the fictional Grifols Plasma Supply demo. Correlate Azure Container Apps 5xx telemetry with structured logs by correlation ID, requisition ID, shipment ID, synthetic distribution center, error code, and RootCauseClue. Inspect the connected repository main branch and cite file:line evidence. Treat all data as synthetic. In Review mode, propose the reversible mitigation of setting DEMO_COLD_CHAIN_FAILURE_RATE to 0; never execute a write without explicit approval.
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
$verifiedCodeAnalyzer = Invoke-AgentApi -Method Get -Path '/api/v2/extendedAgent/agents/code-analyzer' -Body $null
if ((Get-ObjectProperty -InputObject $verifiedCodeAnalyzer -Name @('name')) -ne 'code-analyzer') {
    throw 'Data-plane verification failed for the code-analyzer subagent.'
}
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
$verifiedIncidentFilter = Invoke-AgentApi -Method Get -Path '/api/v2/extendedAgent/incidentFilters/grifols-cold-chain-sev2' -Body $null
$verifiedFilterProperties = Get-ObjectProperty -InputObject $verifiedIncidentFilter -Name @('properties')
if ((Get-ObjectProperty -InputObject $verifiedIncidentFilter -Name @('name')) -ne 'grifols-cold-chain-sev2' -or
    (Get-ObjectProperty -InputObject $verifiedFilterProperties -Name @('agentMode')) -ne 'Review') {
    throw 'Data-plane verification failed for the grifols-cold-chain-sev2 Review incident filter.'
}
Write-Host 'Data plane validated: Sev2 Review incident filter configured.'

$httpTriggerBody = @{
    name = 'grifols-controlled-issue'
    description = 'Investigate a controlled synthetic incident from GitHub Issues or workflow dispatch.'
    agentPrompt = 'Analyze this controlled synthetic incident using Azure Monitor telemetry and the connected repository. Return evidence and a Review-mode mitigation proposal.'
    agent = 'code-analyzer'
    agentMode = 'Review'
}
$triggerList = Invoke-AgentApi -Method Get -Path '/api/v1/httptriggers' -Body $null
$existingTrigger = Find-ControlledTrigger -Triggers (Get-TriggerItems -TriggerList $triggerList)
$triggerId = $null
if ($null -ne $existingTrigger) {
    $existingTriggerProperties = Get-ObjectProperty -InputObject $existingTrigger -Name @('properties')
    $triggerId = Get-ObjectProperty -InputObject $existingTrigger -Name @('triggerId', 'id')
    if ([string]::IsNullOrWhiteSpace($triggerId)) {
        $triggerId = Get-ObjectProperty -InputObject $existingTriggerProperties -Name @('triggerId', 'id')
    }
    if ([string]::IsNullOrWhiteSpace($triggerId)) {
        throw 'Existing controlled HTTP trigger did not expose a trigger ID.'
    }
    Invoke-AgentApi -Method Put -Path "/api/v1/httptriggers/$triggerId" -Body $httpTriggerBody | Out-Null
    Write-Host "Updated existing controlled HTTP trigger '$triggerId'."
} else {
    $createdTrigger = Invoke-AgentApi -Method Post -Path '/api/v1/httptriggers/create' -Body $httpTriggerBody
    $createdTriggerProperties = Get-ObjectProperty -InputObject $createdTrigger -Name @('properties')
    $triggerId = Get-ObjectProperty -InputObject $createdTrigger -Name @('triggerId', 'id')
    if ([string]::IsNullOrWhiteSpace($triggerId)) {
        $triggerId = Get-ObjectProperty -InputObject $createdTriggerProperties -Name @('triggerId', 'id')
    }
    if ([string]::IsNullOrWhiteSpace($triggerId)) {
        throw 'HTTP trigger creation did not return a trigger ID.'
    }
    Write-Host "Created controlled HTTP trigger '$triggerId'."
}

$verifiedTriggerList = Invoke-AgentApi -Method Get -Path '/api/v1/httptriggers' -Body $null
$verifiedTrigger = Find-ControlledTrigger -Triggers (Get-TriggerItems -TriggerList $verifiedTriggerList)
if ($null -eq $verifiedTrigger) {
    throw 'HTTP trigger verification failed: grifols-controlled-issue was not found.'
}
$verifiedTriggerProperties = Get-ObjectProperty -InputObject $verifiedTrigger -Name @('properties')
$verifiedTriggerId = Get-ObjectProperty -InputObject $verifiedTrigger -Name @('triggerId', 'id')
if ([string]::IsNullOrWhiteSpace($verifiedTriggerId)) {
    $verifiedTriggerId = Get-ObjectProperty -InputObject $verifiedTriggerProperties -Name @('triggerId', 'id')
}
if ([string]::IsNullOrWhiteSpace($verifiedTriggerId)) {
    throw 'HTTP trigger verification failed: trigger ID was empty.'
}

$triggerUrl = "$script:AgentEndpoint/api/v1/httptriggers/trigger/$verifiedTriggerId"
if ($SetGitHubSecret) {
    $triggerUrl | gh secret set SRE_TRIGGER_URL --repo $RepositoryFullName
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to set GitHub Actions secret SRE_TRIGGER_URL.'
    }
    Write-Host "GitHub Actions secret SRE_TRIGGER_URL set for $RepositoryFullName without printing the trigger URL."
} else {
    Write-Warning "HTTP trigger verified but GitHub secret was not changed. Rerun with -SetGitHubSecret, or run 'gh secret set SRE_TRIGGER_URL --repo $RepositoryFullName' and paste the trigger URL from the agent trigger settings."
}
