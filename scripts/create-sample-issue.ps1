#requires -Version 7.2
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $Repository = 'marioaguileraaa/grifols-sre-agent-demo'
)

$title = '[SYNTHETIC] Cold-chain dispatch reservation returns 503'
$body = @'
## Synthetic incident

The fictional Grifols Plasma Supply demo is returning `COLD_CHAIN_GATEWAY_UNAVAILABLE` from the final cold-chain dispatch reservation.

## Safety

- Synthetic data only
- No patient or clinical data
- Review-mode investigation; mitigation requires approval
'@

if ($PSCmdlet.ShouldProcess($Repository, 'Create controlled synthetic incident issue')) {
    gh label create sre-investigate `
        --repo $Repository `
        --description 'Allow the SRE Agent to investigate a synthetic demo issue' `
        --color 0E8A16 `
        --force
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to ensure the sre-investigate label exists.'
    }

    gh issue create `
        --repo $Repository `
        --title $title `
        --body $body `
        --label sre-investigate
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to create the sample synthetic incident issue.'
    }
}
