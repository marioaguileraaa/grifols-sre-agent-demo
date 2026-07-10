[CmdletBinding()]
param(
    [string]$Repository = 'marioaguileraaa/grifols-sre-agent-demo',
    [string]$Title = '[SYNTHETIC] Investigate cold-chain reservation 5xx'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
. (Join-Path $PSScriptRoot 'Common.ps1')

Assert-Command -Name 'gh'
if ($Title -notmatch '^\[SYNTHETIC\]') {
    throw 'The sample issue title must retain the [SYNTHETIC] guard.'
}

$body = @'
## Synthetic incident

This issue describes only the fictional Grifols Plasma Supply demonstration.

- Alert: `alert-grifols-cold-chain-5xx-v1`
- Expected code: `COLD_CHAIN_GATEWAY_UNAVAILABLE`
- Runbook: `docs/runbooks/cold-chain-reservation-5xx.md`
- Data classification: synthetic

## Investigation

- [ ] Correlate a response correlation ID with `ContainerAppConsoleLogs_CL`.
- [ ] Verify the active backend revision and `DEMO_COLD_CHAIN_FAILURE_RATE`.
- [ ] Propose mitigation in Review mode.
- [ ] Confirm a successful shipment after approved recovery.
'@

gh label create 'sre-investigate' `
    --repo $Repository `
    --description 'Trigger the synthetic Azure SRE Agent investigation' `
    --color '0E8A16' `
    --force
gh issue create --repo $Repository --title $Title --body $body --label 'sre-investigate'
