using System.ComponentModel.DataAnnotations;

namespace GrifolsPlasmaSupply.Api.Models;

public sealed record DistributionCenter(
    string Id,
    string Name,
    string City,
    string Country,
    string Region,
    string TemperatureCapability,
    bool IsOperational);

public sealed record TherapySupply(
    string Id,
    string DistributionCenterId,
    string Name,
    string Category,
    string Packaging,
    string StorageRange,
    int AvailableUnits);

public sealed class RequisitionLine
{
    [Required, MinLength(1)]
    public string TherapySupplyId { get; init; } = string.Empty;

    [Range(1, 500)]
    public int Quantity { get; init; }
}

public sealed class CreateReplenishmentRequisitionRequest
{
    [Required, MinLength(1)]
    public string DistributionCenterId { get; init; } = string.Empty;

    [Required, MinLength(1)]
    public string DestinationFacility { get; init; } = string.Empty;

    [Required, MinLength(1)]
    public List<RequisitionLine> Lines { get; init; } = [];
}

public sealed record ReplenishmentRequisition(
    string Id,
    string DistributionCenterId,
    string DestinationFacility,
    IReadOnlyList<RequisitionLine> Lines,
    DateTimeOffset CreatedAt,
    string Status);

public sealed class DispatchReservationRequest
{
    [Required, MinLength(1)]
    public string RequisitionId { get; init; } = string.Empty;

    [Required, MinLength(1)]
    public string DestinationFacility { get; init; } = string.Empty;

    [Required, MinLength(1)]
    public string DeliveryWindow { get; init; } = string.Empty;

    [Required, MinLength(1)]
    public string ReceivingContact { get; init; } = string.Empty;

    [Required, RegularExpression("^(standard|urgent)$")]
    public string Priority { get; init; } = "standard";

    [Required, MinLength(1)]
    public string Packaging { get; init; } = string.Empty;

    [MaxLength(500)]
    public string DispatchNotes { get; init; } = string.Empty;
}

public enum ShipmentStatus
{
    Reserved,
    Prepared,
    InTransit,
    Delivered
}

public sealed record TrackingMilestone(
    ShipmentStatus Status,
    DateTimeOffset Timestamp,
    string Description);

public sealed record Shipment(
    string Id,
    string TrackingCode,
    string RequisitionId,
    string DistributionCenterId,
    string DestinationFacility,
    string DeliveryWindow,
    string Packaging,
    ShipmentStatus Status,
    DateTimeOffset CreatedAt,
    IReadOnlyList<TrackingMilestone> TrackingMilestones);

public sealed record ApiError(
    string Code,
    string Message,
    string CorrelationId,
    DateTimeOffset Timestamp);
