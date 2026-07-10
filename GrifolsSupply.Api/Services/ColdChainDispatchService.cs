using System.Collections.Concurrent;
using System.Security.Cryptography;
using System.Text;
using GrifolsSupply.Api.Models;
using GrifolsSupply.Api.Options;
using Microsoft.Extensions.Options;

namespace GrifolsSupply.Api.Services;

public sealed class ColdChainDispatchService(
    IOptions<ColdChainDemoOptions> options,
    ILogger<ColdChainDispatchService> logger)
{
    public const string FailureCode = "COLD_CHAIN_GATEWAY_UNAVAILABLE";
    public const string SafeFailureMessage = "The synthetic cold-chain reservation gateway is temporarily unavailable.";
    private const string RootCauseClue = "SyntheticGatewayRoute=demo-cold-chain-reservation.invalid; FailureMode=ConfiguredFailureRate";
    private static readonly ConcurrentDictionary<string, Shipment> Shipments = new();

    public DispatchResult Reserve(ColdChainDispatchRequest request, string correlationId)
    {
        var center = SyntheticCatalog.DistributionCenters.SingleOrDefault(item => item.Id == request.DistributionCenterId);
        if (center is null)
        {
            return DispatchResult.Invalid("Unknown synthetic distribution center.");
        }

        if (ShouldFail(request, options.Value.FailureRate))
        {
            logger.LogError(
                "Cold-chain dispatch reservation failed. CorrelationId={CorrelationId} RequisitionId={RequisitionId} DistributionCenter={DistributionCenter} ErrorCode={ErrorCode} RootCauseClue={RootCauseClue}",
                correlationId,
                request.RequisitionId,
                center.Name,
                FailureCode,
                RootCauseClue);

            return DispatchResult.Failed(new DispatchFailure(
                FailureCode,
                SafeFailureMessage,
                correlationId,
                DateTimeOffset.UtcNow));
        }

        var shipment = new Shipment
        {
            Id = $"SHP-{Guid.NewGuid():N}"[..16].ToUpperInvariant(),
            TrackingId = $"GPS-{DateTimeOffset.UtcNow:yyyyMMdd}-{Guid.NewGuid():N}"[..22].ToUpperInvariant(),
            RequisitionId = request.RequisitionId,
            DistributionCenterId = center.Id,
            DistributionCenterName = center.Name,
            DestinationFacility = request.DestinationFacility,
            CorrelationId = correlationId,
            EstimatedArrival = DateTimeOffset.UtcNow.AddHours(8)
        };
        Shipments[shipment.TrackingId] = shipment;

        logger.LogInformation(
            "Cold-chain dispatch reserved. CorrelationId={CorrelationId} RequisitionId={RequisitionId} ShipmentId={ShipmentId} TrackingId={TrackingId} DistributionCenter={DistributionCenter}",
            correlationId,
            request.RequisitionId,
            shipment.Id,
            shipment.TrackingId,
            center.Name);

        return DispatchResult.Succeeded(shipment);
    }

    public Shipment? Find(string trackingId) =>
        Shipments.TryGetValue(trackingId, out var shipment) ? shipment : null;

    private static bool ShouldFail(ColdChainDispatchRequest request, int failureRate)
    {
        if (failureRate == 0)
        {
            return false;
        }

        if (failureRate == 100)
        {
            return true;
        }

        var hash = SHA256.HashData(Encoding.UTF8.GetBytes($"{request.RequisitionId}:{request.DistributionCenterId}"));
        return BitConverter.ToUInt32(hash, 0) % 100 < failureRate;
    }
}

public sealed record DispatchResult(Shipment? Shipment, DispatchFailure? Failure, string? ValidationError)
{
    public static DispatchResult Succeeded(Shipment shipment) => new(shipment, null, null);
    public static DispatchResult Failed(DispatchFailure failure) => new(null, failure, null);
    public static DispatchResult Invalid(string message) => new(null, null, message);
}
