namespace GrifolsSupply.Api.Models;

public sealed class DistributionCenter
{
    public int Id { get; init; }
    public required string Code { get; init; }
    public required string Name { get; init; }
    public required string Description { get; init; }
    public required string Region { get; init; }
    public required string Address { get; init; }
    public required string ServiceWindow { get; init; }
    public string ColdChainRange { get; init; } = "2-8 C";
    public bool IsOperational { get; init; } = true;
}
