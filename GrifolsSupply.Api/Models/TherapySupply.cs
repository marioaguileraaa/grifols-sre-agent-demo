namespace GrifolsSupply.Api.Models;

public sealed class TherapySupply
{
    public int Id { get; init; }
    public required string Sku { get; init; }
    public required string Name { get; init; }
    public required string Description { get; init; }
    public required string Category { get; init; }
    public required string UnitOfMeasure { get; init; }
    public int AvailableUnits { get; init; }
    public int DistributionCenterId { get; init; }
    public bool IsAvailable { get; init; } = true;
}
