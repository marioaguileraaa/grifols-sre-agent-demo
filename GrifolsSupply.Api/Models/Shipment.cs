namespace GrifolsSupply.Api.Models;

public enum ShipmentStatus
{
    DispatchReserved = 1,
    ColdChainPrepared = 2,
    InTransit = 3,
    Delivered = 4,
    Cancelled = 5
}

public sealed class Shipment
{
    public required string Id { get; init; }
    public required string TrackingId { get; init; }
    public required string RequisitionId { get; init; }
    public int DistributionCenterId { get; init; }
    public required string DistributionCenterName { get; init; }
    public required string DestinationFacility { get; init; }
    public required string CorrelationId { get; init; }
    public ShipmentStatus Status { get; set; } = ShipmentStatus.DispatchReserved;
    public DateTimeOffset ReservedAt { get; init; } = DateTimeOffset.UtcNow;
    public DateTimeOffset EstimatedArrival { get; init; }
}
