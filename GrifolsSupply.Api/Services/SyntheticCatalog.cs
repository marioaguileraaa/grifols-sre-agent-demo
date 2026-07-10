using GrifolsSupply.Api.Models;

namespace GrifolsSupply.Api.Services;

public static class SyntheticCatalog
{
    public static readonly IReadOnlyList<DistributionCenter> DistributionCenters =
    [
        new()
        {
            Id = 1,
            Code = "BCN-POC",
            Name = "Barcelona Plasma Operations Center",
            Description = "Fictional Iberian replenishment and temperature-controlled dispatch hub.",
            Region = "Southern Europe",
            Address = "Synthetic Logistics Campus, Barcelona",
            ServiceWindow = "Same-day reservation before 14:00 CET"
        },
        new()
        {
            Id = 2,
            Code = "CLY-DC",
            Name = "Clayton Distribution Center",
            Description = "Fictional North American inventory and cold-chain coordination center.",
            Region = "North America",
            Address = "Synthetic Biologics Parkway, Clayton",
            ServiceWindow = "Next available validated lane"
        },
        new()
        {
            Id = 3,
            Code = "DUB-ESH",
            Name = "Dublin European Supply Hub",
            Description = "Fictional European reserve stock and dispatch planning hub.",
            Region = "Northern Europe",
            Address = "Synthetic Supply Park, Dublin",
            ServiceWindow = "Priority reservation before 15:00 GMT"
        }
    ];

    public static readonly IReadOnlyList<TherapySupply> TherapySupplies =
    [
        Supply(1, "SYN-IG-100", "Immunoglobulin Supply - Standard Pack", "Immunoglobulin Supply", 1, 180),
        Supply(2, "SYN-ALB-050", "Albumin Solution Supply - Standard Pack", "Albumin Solution Supply", 1, 240),
        Supply(3, "SYN-COAG-025", "Coagulation Therapy Supply - Standard Pack", "Coagulation Therapy Supply", 1, 90),
        Supply(4, "SYN-IG-200", "Immunoglobulin Supply - Reserve Pack", "Immunoglobulin Supply", 2, 210),
        Supply(5, "SYN-ALB-100", "Albumin Solution Supply - Reserve Pack", "Albumin Solution Supply", 2, 320),
        Supply(6, "SYN-COAG-050", "Coagulation Therapy Supply - Reserve Pack", "Coagulation Therapy Supply", 2, 110),
        Supply(7, "SYN-IG-300", "Immunoglobulin Supply - EU Pack", "Immunoglobulin Supply", 3, 160),
        Supply(8, "SYN-ALB-150", "Albumin Solution Supply - EU Pack", "Albumin Solution Supply", 3, 280),
        Supply(9, "SYN-COAG-075", "Coagulation Therapy Supply - EU Pack", "Coagulation Therapy Supply", 3, 100)
    ];

    private static TherapySupply Supply(int id, string sku, string name, string category, int centerId, int units) =>
        new()
        {
            Id = id,
            Sku = sku,
            Name = name,
            Category = category,
            Description = "Synthetic demonstration inventory; not a real product or clinical recommendation.",
            UnitOfMeasure = "demo shipping unit",
            AvailableUnits = units,
            DistributionCenterId = centerId
        };
}
