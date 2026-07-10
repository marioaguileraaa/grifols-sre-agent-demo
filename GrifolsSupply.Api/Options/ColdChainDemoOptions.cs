using Microsoft.Extensions.Options;

namespace GrifolsSupply.Api.Options;

public sealed class ColdChainDemoOptions
{
    public int FailureRate { get; set; }
}

public sealed class ColdChainDemoOptionsValidator : IValidateOptions<ColdChainDemoOptions>
{
    public ValidateOptionsResult Validate(string? name, ColdChainDemoOptions options) =>
        options.FailureRate is >= 0 and <= 100
            ? ValidateOptionsResult.Success
            : ValidateOptionsResult.Fail("DEMO_COLD_CHAIN_FAILURE_RATE must be an integer from 0 through 100.");
}
