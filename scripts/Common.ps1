Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

function Assert-Command {
    param([Parameter(Mandatory)][string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' is not installed or not available on PATH."
    }
}

function Assert-AzureTarget {
    param(
        [Parameter(Mandatory)][string]$SubscriptionId,
        [Parameter(Mandatory)][string]$ResourceGroup,
        [Parameter(Mandatory)][string]$Location
    )

    Assert-Command -Name 'az'
    $account = az account show --output json | ConvertFrom-Json
    if ($account.id -ne $SubscriptionId) {
        throw "Azure CLI subscription mismatch. Expected $SubscriptionId, found $($account.id)."
    }

    $group = az group show --name $ResourceGroup --subscription $SubscriptionId --output json | ConvertFrom-Json
    if ($group.name -ne $ResourceGroup -or (($group.location -replace '\s', '') -ne $Location)) {
        throw "Target guard failed for resource group '$ResourceGroup' in '$Location'."
    }
}

function Wait-ContainerAppReady {
    param(
        [Parameter(Mandatory)][string]$SubscriptionId,
        [Parameter(Mandatory)][string]$ResourceGroup,
        [Parameter(Mandatory)][string]$AppName,
        [int]$TimeoutSeconds = 600
    )

    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $state = az containerapp show `
            --subscription $SubscriptionId `
            --resource-group $ResourceGroup `
            --name $AppName `
            --query "{latest:properties.latestRevisionName,ready:properties.latestReadyRevisionName,provisioning:properties.provisioningState}" `
            --output json | ConvertFrom-Json
        if ($state.provisioning -eq 'Succeeded' -and
            -not [string]::IsNullOrWhiteSpace($state.latest) -and
            $state.latest -eq $state.ready) {
            Write-Host "$AppName ready revision: $($state.ready)"
            return
        }
        Start-Sleep -Seconds 10
    } while ([DateTimeOffset]::UtcNow -lt $deadline)

    throw "Container App '$AppName' did not report a ready revision within $TimeoutSeconds seconds."
}

function Get-ContainerAppUrl {
    param(
        [Parameter(Mandatory)][string]$SubscriptionId,
        [Parameter(Mandatory)][string]$ResourceGroup,
        [Parameter(Mandatory)][string]$AppName
    )
    $fqdn = az containerapp show `
        --subscription $SubscriptionId `
        --resource-group $ResourceGroup `
        --name $AppName `
        --query "properties.configuration.ingress.fqdn" `
        --output tsv
    if ([string]::IsNullOrWhiteSpace($fqdn)) {
        throw "No ingress FQDN was found for '$AppName'."
    }
    return "https://$fqdn"
}

function New-SyntheticRequisition {
    param([Parameter(Mandatory)][string]$BackendUrl)
    $payload = @{
        distributionCenterId = 'BCN-01'
        destinationFacility = 'Synthetic Hospital Receiving Center'
        lines = @(
            @{
                therapySupplyId = 'TS-IMM-100'
                quantity = 12
            }
        )
    } | ConvertTo-Json -Depth 5

    return Invoke-RestMethod `
        -Uri "$BackendUrl/api/requisitions" `
        -Method Post `
        -ContentType 'application/json' `
        -Body $payload
}

function New-SyntheticDispatchBody {
    param([Parameter(Mandatory)][string]$RequisitionId)
    return @{
        requisitionId = $RequisitionId
        destinationFacility = 'Synthetic Hospital Receiving Center'
        deliveryWindow = 'Next validated 4-hour window'
        receivingContact = 'Synthetic Logistics Desk'
        priority = 'urgent'
        packaging = 'Temperature-controlled case'
        dispatchNotes = 'Synthetic cold-chain SRE demonstration'
    } | ConvertTo-Json -Depth 5
}
