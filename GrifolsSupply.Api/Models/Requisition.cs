namespace GrifolsSupply.Api.Models;

public sealed class RequisitionItem
{
    public int TherapySupplyId { get; init; }
    public required TherapySupply TherapySupply { get; init; }
    public int Quantity { get; set; }
    public string HandlingNotes { get; set; } = string.Empty;
}

public sealed class Requisition
{
    public required string Id { get; init; }
    public required string RequestingFacility { get; init; }
    public int DistributionCenterId { get; init; }
    public List<RequisitionItem> Items { get; init; } = [];
    public DateTimeOffset CreatedAt { get; init; } = DateTimeOffset.UtcNow;
    public string Status { get; set; } = "Draft";
}
