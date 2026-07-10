#requires -Version 7.2
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $Repository = 'marioaguileraaa/grifols-sre-agent-demo'
)

$title = '[SRE demo] Cold-chain dispatch reservation returns 503'
$body = @'
## Synthetic incident

The fictional Grifols Plasma Supply demo is returning `COLD_CHAIN_GATEWAY_UNAVAILABLE` from the final cold-chain dispatch reservation.

## Safety

- Synthetic data only
- No patient or clinical data
- Review-mode investigation; mitigation requires approval
'@

if ($PSCmdlet.ShouldProcess($Repository, 'Create controlled incident issue')) {
    gh issue create `
        --repo $Repository `
        --title $title `
        --body $body `
        --label incident `
        --label sre-agent-demo
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to create the sample incident issue.'
    }
}
