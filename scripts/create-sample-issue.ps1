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

if ($PSCmdlet.ShouldProcess($Repository, 'Create controlled incident issue')) {
    $issueUrl = gh issue create `
        --repo $Repository `
        --title $title `
        --body $body
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to create the sample incident issue.'
    }

    gh issue edit $issueUrl --add-label sre-investigate
    if ($LASTEXITCODE -ne 0) {
        throw "Issue '$issueUrl' was created, but the sre-investigate label could not be added."
    }
}
