#requires -Version 7.2
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path $PSScriptRoot -Parent
$bridgePath = Join-Path $repositoryRoot 'infra\trigger-bridge.bicep'
$configurationPath = Join-Path $repositoryRoot 'scripts\configure-sre-agent.ps1'
$workflowPath = Join-Path $repositoryRoot '.github\workflows\sre-agent-investigate.yml'
$readmePath = Join-Path $repositoryRoot 'README.md'
$runbookPath = Join-Path $repositoryRoot 'docs\runbooks\cold-chain-reservation-5xx.md'

$bridge = Get-Content $bridgePath -Raw
$configuration = Get-Content $configurationPath -Raw
$workflow = Get-Content $workflowPath -Raw
$documentation = (Get-Content $readmePath -Raw) + (Get-Content $runbookPath -Raw)

function Assert-Match {
    param(
        [Parameter(Mandatory)]
        [string] $Text,
        [Parameter(Mandatory)]
        [string] $Pattern,
        [Parameter(Mandatory)]
        [string] $Message
    )

    if ($Text -notmatch $Pattern) {
        throw $Message
    }
}

function Assert-NotMatch {
    param(
        [Parameter(Mandatory)]
        [string] $Text,
        [Parameter(Mandatory)]
        [string] $Pattern,
        [Parameter(Mandatory)]
        [string] $Message
    )

    if ($Text -match $Pattern) {
        throw $Message
    }
}

Assert-Match $bridge '(?s)@secure\(\).*param protectedTriggerUrl string' 'The protected SRE trigger URL must be a secure Bicep parameter.'
Assert-Match $bridge "resource bridge 'Microsoft\.Logic/workflows@2019-05-01'" 'The bridge must be a Consumption Logic App workflow.'
Assert-Match $bridge "(?s)identity:\s*\{\s*type:\s*'SystemAssigned'" 'The Logic App must use a system-assigned identity.'
Assert-Match $bridge "(?s)manual:\s*\{.*type:\s*'Request'.*schema:\s*\{\s*type:\s*'object'" 'The bridge Request trigger must accept a JSON object.'
Assert-Match $bridge "body:\s*'@triggerBody\(\)'" 'The bridge must forward the original request body.'
Assert-Match $bridge "(?s)authentication:\s*\{\s*type:\s*'ManagedServiceIdentity'\s*audience:\s*'https://azuresre\.dev'" 'The HTTP action must use managed identity for the SRE Agent audience.'
Assert-Match $bridge "(?s)retryPolicy:\s*\{\s*type:\s*'none'" 'The non-idempotent SRE trigger POST must not be retried automatically.'
Assert-Match $bridge "statusCode:\s*'@outputs\(\\'Forward_to_SRE_Agent\\'\)\?\[\\'statusCode\\'\]'" 'Successful downstream status must be returned unchanged.'
Assert-Match $bridge "(?s)Return_SRE_Agent_failure:.*statusCode:\s*'@coalesce\(.*502\)'.*Forward_to_SRE_Agent:\s*\[\s*'Failed'" 'Downstream failures must be returned without success shaping.'
Assert-Match $bridge "(?s)Return_SRE_Agent_timeout:.*statusCode:\s*504.*Forward_to_SRE_Agent:\s*\[\s*'TimedOut'" 'Timeouts must have an explicit non-success response.'
Assert-Match $bridge '2d84a65a-63b2-4343-bbb6-31105d857bc1' 'The bridge must use SRE Agent Standard User.'
Assert-Match $bridge "(?s)resource bridgeSreAgentStandardUser .*scope:\s*sreAgent" 'The Standard User role assignment must be scoped to the agent.'
Assert-NotMatch $bridge 'e79298df-d852-4c6d-84f9-5d13249d1e55|scope:\s*resourceGroup\(\)' 'The bridge must not receive Administrator or resource-group scope.'
Assert-NotMatch $bridge '(?im)output .*callback|listCallbackUrl' 'The Bicep module must never output the callback signature.'

$secretReferences = [regex]::Matches($workflow, 'secrets\.([A-Za-z0-9_]+)')
if ($secretReferences.Count -ne 1 -or $secretReferences[0].Groups[1].Value -ne 'SRE_TRIGGER_URL') {
    throw 'The workflow must reference exactly one secret: SRE_TRIGGER_URL.'
}
Assert-NotMatch $workflow '(?i)azure/login|id-token:|client-id:|tenant-id:|subscription-id:|Authorization:' 'The GitHub workflow must contain no Azure authentication.'
Assert-Match $workflow 'test "\$status" = "202"' 'The workflow must continue to require HTTP 202.'
Assert-Match $workflow "\.success == true.*\.threadId" 'The workflow must continue to validate success and threadId.'

Assert-Match $configuration 'protectedTriggerUrl = @\{ value = \$triggerUrl \}' 'The protected trigger URL must be passed only in the in-memory ARM deployment body.'
Assert-NotMatch $configuration '(?m)^\s*az (?:deployment|rest).*\$triggerUrl|protectedTriggerUrl=\$triggerUrl' 'The protected trigger URL must not appear in a child-process command line.'
Assert-Match $configuration '/triggers/manual/listCallbackUrl\?api-version=\$logicAppApiVersion' 'The callback must be obtained through ARM listCallbackUrl.'
Assert-Match $configuration '\$callbackUrl\s*\|\s*gh secret set SRE_TRIGGER_URL' 'The Logic App callback must be piped to the GitHub secret.'
Assert-NotMatch $configuration '\$triggerUrl\s*\|\s*gh secret set SRE_TRIGGER_URL' 'The protected SRE trigger URL must not be stored in GitHub.'
Assert-Match $configuration '(?s)if \(-not \$SetGitHubSecret\).*throw ''INCOMPLETE:' 'Missing -SetGitHubSecret must fail closed.'
Assert-Match $configuration '(?s)--scope \$agentResourceId.*roleDefinitionId -match "/\$sreStandardUserRoleId\$"' 'The script must verify Standard User at the exact agent scope.'
Assert-Match $configuration '(?s)--assignee-object-id \$bridgePrincipalId\s*`\s*--all.*\$unexpectedBridgeRoleAssignments.*Keep only SRE Agent Standard User' 'The script must fail if the bridge identity has any additional role assignment.'
Assert-Match $configuration '(?s)\$oauthUri\.Scheme -eq ''https''.*\$oauthUri\.Host -eq ''github\.com''.*\$oauthUri\.IsDefaultPort.*StartsWith\(''/login/oauth/''' 'Interactive OAuth must be restricted to GitHub HTTPS authorization paths.'
Assert-Match $configuration '(?s)TryCreate\(\$callbackUrl\.Trim\(\).*\$callbackUri\.Scheme -ne ''https''.*\$callbackUri\.Query -notmatch ''\(\^\\\?\|&\)sig=' 'Only a signed HTTPS callback may be stored in GitHub.'
Assert-NotMatch $configuration '(?im)Write-(?:Host|Output|Verbose|Information|Debug).*\$(?:accessToken|triggerUrl|callbackUrl|oauthUrl|oauthUri)' 'Sensitive tokens and URLs must never be written to output.'

Assert-NotMatch $documentation '(?i)webhook público|endpoint público' 'Documentation must not describe the protected trigger as public or anonymous.'
Assert-Match $documentation '401 Authentication failed' 'Documentation must explain unauthenticated trigger failures.'
Assert-Match $documentation 'SRE Agent Standard User' 'Documentation must state the bridge least-privilege role.'
Assert-Match $documentation 'un solo secreto|único secreto' 'Documentation must preserve the one-secret GitHub contract.'

Write-Host 'Trigger bridge contract assertions passed.'
