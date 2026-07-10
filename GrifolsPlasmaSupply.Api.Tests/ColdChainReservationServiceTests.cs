using GrifolsPlasmaSupply.Api.Models;
using GrifolsPlasmaSupply.Api.Options;
using GrifolsPlasmaSupply.Api.Services;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using Xunit;

namespace GrifolsPlasmaSupply.Api.Tests;

public sealed class ColdChainReservationServiceTests
{
    [Fact]
    public void Stable_bucket_is_reproducible_and_controls_intermediate_rate()
    {
        const string requisitionKey = "REQ-STABLE-DEMO";
        var first = ColdChainReservationService.StableBucket(requisitionKey);
        var second = ColdChainReservationService.StableBucket(requisitionKey);

        Assert.Equal(first, second);
        Assert.InRange(first, 0, 99);
        Assert.True(first < Math.Min(first + 1, 100));
    }

    [Fact]
    public void Intermediate_failure_never_persists_a_shipment()
    {
        var store = new DemoSupplyStore();
        var catalog = new SyntheticCatalog();
        var requisition = store.AddRequisition(new CreateReplenishmentRequisitionRequest
        {
            DistributionCenterId = "BCN-01",
            DestinationFacility = "Synthetic Hospital Receiving Center",
            Lines = [new RequisitionLine { TherapySupplyId = "TS-IMM-100", Quantity = 1 }]
        });
        var bucket = ColdChainReservationService.StableBucket(requisition.Id);
        var rate = Math.Min(bucket + 1, 100);
        var service = new ColdChainReservationService(
            store,
            catalog,
            Microsoft.Extensions.Options.Options.Create(
                new ColdChainDemoOptions { ConfiguredFailureRate = rate.ToString() }),
            NullLogger<ColdChainReservationService>.Instance);

        var result = service.Reserve(new DispatchReservationRequest
        {
            RequisitionId = requisition.Id,
            DestinationFacility = requisition.DestinationFacility,
            DeliveryWindow = "synthetic-window",
            ReceivingContact = "Synthetic Logistics Desk",
            Priority = "standard",
            Packaging = "Temperature-controlled case"
        }, "test-correlation");

        Assert.False(result.Success);
        Assert.Null(result.Shipment);
        Assert.Empty(store.GetShipments());
    }
}
