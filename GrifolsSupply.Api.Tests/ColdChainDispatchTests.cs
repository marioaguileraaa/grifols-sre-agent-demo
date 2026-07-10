using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using GrifolsSupply.Api.Models;
using GrifolsSupply.Api.Options;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using Xunit;

namespace GrifolsSupply.Api.Tests;

public sealed class ColdChainDispatchTests
{
    [Fact]
    public async Task Healthy_configuration_returns_shipment_and_tracking_id()
    {
        await using var factory = CreateFactory(0);
        using var client = factory.CreateClient();

        var response = await client.PostAsJsonAsync("/api/cold-chain-dispatch", ValidRequest("REQ-HEALTHY"));

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var shipment = await response.Content.ReadFromJsonAsync<Shipment>();
        Assert.NotNull(shipment);
        Assert.StartsWith("GPS-", shipment.TrackingId);
        Assert.Equal("REQ-HEALTHY", shipment.RequisitionId);
    }

    [Fact]
    public async Task One_hundred_percent_failure_returns_stable_safe_503()
    {
        await using var factory = CreateFactory(100);
        using var client = factory.CreateClient();
        const string correlationId = "test-correlation-503";
        client.DefaultRequestHeaders.Add("X-Correlation-ID", correlationId);

        var response = await client.PostAsJsonAsync("/api/cold-chain-dispatch", ValidRequest("REQ-FAIL"));

        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal("COLD_CHAIN_GATEWAY_UNAVAILABLE", body.GetProperty("code").GetString());
        Assert.Equal(correlationId, body.GetProperty("correlationId").GetString());
        Assert.DoesNotContain("secret", body.GetProperty("message").GetString(), StringComparison.OrdinalIgnoreCase);
    }

    [Theory]
    [InlineData(-1)]
    [InlineData(101)]
    public void Failure_rate_validator_rejects_out_of_range_values(int value)
    {
        var result = new ColdChainDemoOptionsValidator().Validate(null, new ColdChainDemoOptions { FailureRate = value });

        Assert.True(result.Failed);
        Assert.Contains("0 through 100", result.FailureMessage);
    }

    private static WebApplicationFactory<Program> CreateFactory(int failureRate) =>
        new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
            builder.ConfigureAppConfiguration((_, configuration) =>
                configuration.AddInMemoryCollection(new Dictionary<string, string?>
                {
                    ["DEMO_COLD_CHAIN_FAILURE_RATE"] = failureRate.ToString()
                })));

    private static ColdChainDispatchRequest ValidRequest(string requisitionId) =>
        new()
        {
            RequisitionId = requisitionId,
            DistributionCenterId = 1,
            DestinationFacility = "Synthetic University Hospital",
            RequestedBy = "Demo Supply Coordinator",
            Items =
            [
                new RequisitionLineRequest
                {
                    TherapySupplyId = 1,
                    Quantity = 8,
                    HandlingNotes = "Maintain validated demo cold-chain lane."
                }
            ]
        };
}
