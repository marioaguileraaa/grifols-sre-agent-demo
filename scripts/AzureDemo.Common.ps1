Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-DemoAzureContext {
    param(
        [Parameter(Mandatory)]
        [string] $SubscriptionId,
        [Parameter(Mandatory)]
        [string] $ResourceGroupName
    )

    $account = az account show --output json | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or $account.id -ne $SubscriptionId) {
        throw "Azure CLI must be signed in to expected subscription '$SubscriptionId'. Current: '$($account.id)'."
    }

    $resourceGroup = az group show --subscription $SubscriptionId --name $ResourceGroupName --output json | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or $resourceGroup.name -ne $ResourceGroupName) {
        throw "Expected resource group '$ResourceGroupName' is not accessible in subscription '$SubscriptionId'."
    }

    Write-Host "Safeguard passed: $($account.name) / $SubscriptionId / $ResourceGroupName"
}

function Wait-ContainerAppRevision {
    param(
        [Parameter(Mandatory)]
        [string] $SubscriptionId,
        [Parameter(Mandatory)]
        [string] $ResourceGroupName,
        [Parameter(Mandatory)]
        [string] $ContainerAppName,
        [int] $TimeoutSeconds = 600
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $revisions = az containerapp revision list `
            --subscription $SubscriptionId `
            --resource-group $ResourceGroupName `
            --name $ContainerAppName `
            --output json | ConvertFrom-Json
        if ($LASTEXITCODE -ne 0) {
            throw "Unable to list revisions for '$ContainerAppName'."
        }

        $latest = $revisions |
            Sort-Object { [DateTimeOffset]$_.properties.createdTime } -Descending |
            Select-Object -First 1
        $readyRunningStates = @('Running', 'RunningAtMinScale', 'RunningAtMaxScale')
        if ($latest.properties.healthState -eq 'Healthy' -and
            $latest.properties.runningState -in $readyRunningStates) {
            Write-Host "Revision ready: $($latest.name)"
            return $latest
        }

        Start-Sleep -Seconds 10
    } while ((Get-Date) -lt $deadline)

    throw "Latest revision for '$ContainerAppName' did not become Healthy/Running in $TimeoutSeconds seconds."
}

function New-DemoDispatchPayload {
    param([string] $RequisitionId = "REQ-DEMO-$([Guid]::NewGuid().ToString('N').Substring(0, 12).ToUpperInvariant())")

    return @{
        requisitionId = $RequisitionId
        distributionCenterId = 1
        destinationFacility = 'Synthetic University Hospital'
        requestedBy = 'SRE Demo Coordinator'
        items = @(
            @{
                therapySupplyId = 1
                quantity = 8
                handlingNotes = 'Synthetic demo request; maintain 2-8 C demonstration lane.'
            }
        )
    }
}
