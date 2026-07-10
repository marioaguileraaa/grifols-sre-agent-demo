using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using GrifolsPlasmaSupply.Api.Models;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Xunit;

namespace GrifolsPlasmaSupply.Api.Tests;

public sealed class SupplyApiTests
{
    private static readonly JsonSerializerOptions JsonOptions = CreateJsonOptions();

    [Fact]
    public async Task Reservation_success_creates_trackable_shipment()
    {
        using var factory = CreateFactory("0");
        using var client = factory.CreateClient();
        var requisition = await CreateRequisition(client);

        var response = await client.PostAsJsonAsync("/api/dispatch-reservations", Dispatch(requisition.Id));

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        Assert.True(response.Headers.Contains("X-Correlation-ID"));
        var shipment = await response.Content.ReadFromJsonAsync<Shipment>(JsonOptions);
        Assert.NotNull(shipment);
        Assert.Equal(requisition.Id, shipment.RequisitionId);
        Assert.NotEmpty(shipment.TrackingMilestones);

        var trackingResponse = await client.GetAsync($"/api/shipments/{shipment.Id}");
        Assert.Equal(HttpStatusCode.OK, trackingResponse.StatusCode);
    }

    [Fact]
    public async Task Forced_failure_returns_structured_503_and_creates_no_shipment()
    {
        using var factory = CreateFactory("100");
        using var client = factory.CreateClient();
        var requisition = await CreateRequisition(client);

        var response = await client.PostAsJsonAsync("/api/dispatch-reservations", Dispatch(requisition.Id));

        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        var error = await response.Content.ReadFromJsonAsync<ApiError>();
        Assert.NotNull(error);
        Assert.Equal("COLD_CHAIN_GATEWAY_UNAVAILABLE", error.Code);
        Assert.Equal(error.CorrelationId, response.Headers.GetValues("X-Correlation-ID").Single());

        var shipments = await client.GetFromJsonAsync<List<Shipment>>("/api/shipments");
        Assert.Empty(shipments!);
    }

    [Theory]
    [InlineData("-1")]
    [InlineData("101")]
    [InlineData("not-an-integer")]
    public void Invalid_failure_rate_stops_application_startup(string configuredValue)
    {
        using var factory = CreateFactory(configuredValue);
        Assert.ThrowsAny<Exception>(() => factory.CreateClient());
    }

    [Fact]
    public async Task Empty_requisition_is_rejected()
    {
        using var factory = CreateFactory("0");
        using var client = factory.CreateClient();

        var response = await client.PostAsJsonAsync("/api/requisitions", new
        {
            distributionCenterId = "BCN-01",
            destinationFacility = "Synthetic Hospital Receiving Center",
            lines = Array.Empty<object>()
        });

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    private static WebApplicationFactory<Program> CreateFactory(string failureRate) =>
        new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
            builder.UseSetting("DEMO_COLD_CHAIN_FAILURE_RATE", failureRate));

    private static async Task<ReplenishmentRequisition> CreateRequisition(HttpClient client)
    {
        var response = await client.PostAsJsonAsync("/api/requisitions", new
        {
            distributionCenterId = "BCN-01",
            destinationFacility = "Synthetic Hospital Receiving Center",
            lines = new[] { new { therapySupplyId = "TS-IMM-100", quantity = 12 } }
        });
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<ReplenishmentRequisition>())!;
    }

    private static object Dispatch(string requisitionId) => new
    {
        requisitionId,
        destinationFacility = "Synthetic Hospital Receiving Center",
        deliveryWindow = "2026-07-11T08:00:00Z/2026-07-11T12:00:00Z",
        receivingContact = "Synthetic Logistics Desk",
        priority = "urgent",
        packaging = "Temperature-controlled case",
        dispatchNotes = "Synthetic SRE demo"
    };

    private static JsonSerializerOptions CreateJsonOptions()
    {
        var options = new JsonSerializerOptions(JsonSerializerDefaults.Web);
        options.Converters.Add(new JsonStringEnumConverter(JsonNamingPolicy.CamelCase));
        return options;
    }
}
