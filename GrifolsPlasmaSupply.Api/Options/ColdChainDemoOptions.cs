using System.Globalization;

namespace GrifolsPlasmaSupply.Api.Options;

public sealed class ColdChainDemoOptions
{
    public string ConfiguredFailureRate { get; set; } = "0";

    public int FailureRate =>
        TryGetFailureRate(out var rate)
            ? rate
            : throw new InvalidOperationException("Cold-chain failure rate configuration is invalid.");

    public bool TryGetFailureRate(out int rate) =>
        int.TryParse(ConfiguredFailureRate, NumberStyles.None, CultureInfo.InvariantCulture, out rate)
        && rate is >= 0 and <= 100;
}
