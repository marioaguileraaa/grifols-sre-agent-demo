using GrifolsPlasmaSupply.Api.Middleware;
using GrifolsPlasmaSupply.Api.Options;
using GrifolsPlasmaSupply.Api.Services;
using Microsoft.AspNetCore.HttpOverrides;
using System.Text.Json;
using System.Text.Json.Serialization;

var builder = WebApplication.CreateBuilder(args);

builder.Logging.ClearProviders();
builder.Logging.AddJsonConsole(options => options.TimestampFormat = "yyyy-MM-ddTHH:mm:ss.fffZ");

builder.Services.AddControllers()
    .AddJsonOptions(options =>
        options.JsonSerializerOptions.Converters.Add(new JsonStringEnumConverter(JsonNamingPolicy.CamelCase)));
builder.Services.AddOpenApi();
builder.Services.AddHealthChecks();
builder.Services.AddSingleton<SyntheticCatalog>();
builder.Services.AddSingleton<DemoSupplyStore>();
builder.Services.AddSingleton<ColdChainReservationService>();
builder.Services
    .AddOptions<ColdChainDemoOptions>()
    .Configure(options =>
        options.ConfiguredFailureRate = builder.Configuration["DEMO_COLD_CHAIN_FAILURE_RATE"] ?? "0")
    .Validate(
        options => options.TryGetFailureRate(out _),
        "DEMO_COLD_CHAIN_FAILURE_RATE must be an integer from 0 through 100.")
    .ValidateOnStart();

builder.Services.Configure<ForwardedHeadersOptions>(options =>
{
    options.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;
    options.KnownNetworks.Clear();
    options.KnownProxies.Clear();
});

builder.Services.AddCors(options =>
{
    options.AddPolicy("Frontend", policy =>
    {
        var configuredOrigins = builder.Configuration.GetSection("AllowedOrigins").Get<string[]>()
            ?? [];
        var origins = configuredOrigins
            .Append("http://localhost:3000")
            .Where(origin => !string.IsNullOrWhiteSpace(origin))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();

        policy.WithOrigins(origins)
            .AllowAnyHeader()
            .AllowAnyMethod();
    });
});

var app = builder.Build();

app.UseForwardedHeaders();
app.UseMiddleware<CorrelationIdMiddleware>();
app.UseCors("Frontend");

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
}

app.MapHealthChecks("/health");
app.MapControllers();

app.Run();

public partial class Program;
