using System.Buffers.Binary;
using System.Security.Cryptography;
using System.Text;
using GrifolsPlasmaSupply.Api.Models;
using GrifolsPlasmaSupply.Api.Options;
using Microsoft.Extensions.Options;

namespace GrifolsPlasmaSupply.Api.Services;

public sealed class ColdChainReservationService(
    DemoSupplyStore store,
    SyntheticCatalog catalog,
    IOptions<ColdChainDemoOptions> options,
    ILogger<ColdChainReservationService> logger)
{
    public const string FailureCode = "COLD_CHAIN_GATEWAY_UNAVAILABLE";
    public const string SourceClue = "Configuration:DEMO_COLD_CHAIN_FAILURE_RATE -> ColdChainReservationGateway";

    public ReservationResult Reserve(DispatchReservationRequest request, string correlationId)
    {
        var requisition = store.GetRequisition(request.RequisitionId)
            ?? throw new KeyNotFoundException("The replenishment requisition does not exist.");
        var center = catalog.FindCenter(requisition.DistributionCenterId)
            ?? throw new InvalidOperationException("The distribution center does not exist.");
        var failureRate = options.Value.FailureRate;
        var bucket = StableBucket(requisition.Id);

        if (failureRate == 100 || failureRate > 0 && bucket < failureRate)
        {
            logger.LogWarning(
                "Cold-chain dispatch reservation failed. CorrelationId={CorrelationId} RequisitionId={RequisitionId} DistributionCenter={DistributionCenter} ErrorCode={ErrorCode} FailureRate={FailureRate} FailureBucket={FailureBucket} SourceClue={SourceClue}",
                correlationId,
                requisition.Id,
                center.Id,
                FailureCode,
                failureRate,
                bucket,
                SourceClue);
            return ReservationResult.Failed(bucket, failureRate);
        }

        var now = DateTimeOffset.UtcNow;
        var shipmentId = $"SHP-{Guid.NewGuid():N}"[..16].ToUpperInvariant();
        var shipment = new Shipment(
            shipmentId,
            $"GPS-{now:yyyyMMdd}-{shipmentId[4..]}",
            requisition.Id,
            center.Id,
            request.DestinationFacility,
            request.DeliveryWindow,
            request.Packaging,
            ShipmentStatus.Reserved,
            now,
            [
                new(ShipmentStatus.Reserved, now, "Cold-chain dispatch capacity reserved"),
                new(ShipmentStatus.Prepared, now.AddHours(2), "Synthetic supply preparation scheduled"),
                new(ShipmentStatus.InTransit, now.AddHours(8), "Temperature-monitored transit scheduled")
            ]);
        store.AddShipment(shipment);

        logger.LogInformation(
            "Cold-chain dispatch reservation succeeded. CorrelationId={CorrelationId} RequisitionId={RequisitionId} ShipmentId={ShipmentId} DistributionCenter={DistributionCenter} FailureRate={FailureRate} FailureBucket={FailureBucket} SourceClue={SourceClue}",
            correlationId,
            requisition.Id,
            shipment.Id,
            center.Id,
            failureRate,
            bucket,
            SourceClue);
        return ReservationResult.Succeeded(shipment, bucket, failureRate);
    }

    public static int StableBucket(string requisitionId)
    {
        var hash = SHA256.HashData(Encoding.UTF8.GetBytes(requisitionId));
        return (int)(BinaryPrimitives.ReadUInt32BigEndian(hash) % 100);
    }
}

public sealed record ReservationResult(bool Success, Shipment? Shipment, int FailureBucket, int FailureRate)
{
    public static ReservationResult Succeeded(Shipment shipment, int bucket, int rate) =>
        new(true, shipment, bucket, rate);

    public static ReservationResult Failed(int bucket, int rate) =>
        new(false, null, bucket, rate);
}
