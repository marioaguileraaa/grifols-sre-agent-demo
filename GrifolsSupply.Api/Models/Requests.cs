using System.ComponentModel.DataAnnotations;

namespace GrifolsSupply.Api.Models;

public sealed class RequisitionLineRequest
{
    [Range(1, int.MaxValue)]
    public int TherapySupplyId { get; init; }

    [Range(1, 500)]
    public int Quantity { get; init; }

    [MaxLength(240)]
    public string HandlingNotes { get; init; } = string.Empty;
}

public sealed class CreateRequisitionRequest
{
    [Required, MaxLength(120)]
    public required string RequestingFacility { get; init; }

    [Range(1, int.MaxValue)]
    public int DistributionCenterId { get; init; }

    [Required, MinLength(1)]
    public required List<RequisitionLineRequest> Items { get; init; }
}

public sealed class ColdChainDispatchRequest
{
    [Required, MaxLength(64)]
    public required string RequisitionId { get; init; }

    [Range(1, int.MaxValue)]
    public int DistributionCenterId { get; init; }

    [Required, MaxLength(120)]
    public required string DestinationFacility { get; init; }

    [Required, MaxLength(100)]
    public required string RequestedBy { get; init; }

    [Required, MinLength(1)]
    public required List<RequisitionLineRequest> Items { get; init; }
}

public sealed record DispatchFailure(
    string Code,
    string Message,
    string CorrelationId,
    DateTimeOffset Timestamp);
