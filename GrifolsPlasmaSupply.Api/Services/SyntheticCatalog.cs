using GrifolsPlasmaSupply.Api.Models;

namespace GrifolsPlasmaSupply.Api.Services;

public sealed class SyntheticCatalog
{
    public IReadOnlyList<DistributionCenter> DistributionCenters { get; } =
    [
        new("BCN-01", "Barcelona Plasma Operations Center", "Barcelona", "Spain", "Southern Europe", "2–8 °C", true),
        new("CLY-01", "Clayton Distribution Center", "Clayton", "United States", "North America", "2–8 °C", true),
        new("DUB-01", "Dublin European Supply Hub", "Dublin", "Ireland", "Northern Europe", "2–8 °C", true)
    ];

    public IReadOnlyList<TherapySupply> TherapySupplies { get; } =
    [
        new("TS-IMM-100", "BCN-01", "Synthetic Immune Therapy Supply", "Immune support", "Temperature-controlled case", "2–8 °C", 240),
        new("TS-ALB-200", "BCN-01", "Synthetic Protein Therapy Supply", "Protein therapy", "Validated cold-chain case", "2–8 °C", 180),
        new("TS-COA-300", "CLY-01", "Synthetic Coagulation Therapy Supply", "Coagulation support", "Monitored transport case", "2–8 °C", 320),
        new("TS-IMM-400", "DUB-01", "Synthetic Specialty Therapy Supply", "Specialty therapy", "Temperature-controlled case", "2–8 °C", 210)
    ];

    public DistributionCenter? FindCenter(string id) =>
        DistributionCenters.FirstOrDefault(center => center.Id.Equals(id, StringComparison.OrdinalIgnoreCase));

    public TherapySupply? FindSupply(string id) =>
        TherapySupplies.FirstOrDefault(supply => supply.Id.Equals(id, StringComparison.OrdinalIgnoreCase));
}
