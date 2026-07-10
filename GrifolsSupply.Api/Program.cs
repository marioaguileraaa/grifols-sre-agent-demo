using GrifolsSupply.Api.Options;
using GrifolsSupply.Api.Services;
using Microsoft.AspNetCore.HttpOverrides;

var builder = WebApplication.CreateBuilder(args);

builder.Logging.ClearProviders();
builder.Logging.AddJsonConsole();

builder.Services.AddControllers();
builder.Services.AddOpenApi();
builder.Services.Configure<ForwardedHeadersOptions>(options =>
{
    options.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;
});

builder.Services
    .AddOptions<ColdChainDemoOptions>()
    .Configure(options =>
    {
        options.FailureRate = builder.Configuration.GetValue<int?>("DEMO_COLD_CHAIN_FAILURE_RATE")
            ?? builder.Configuration.GetValue<int>("Demo:ColdChainFailureRate");
    })
    .ValidateOnStart();
builder.Services.AddSingleton<Microsoft.Extensions.Options.IValidateOptions<ColdChainDemoOptions>, ColdChainDemoOptionsValidator>();
builder.Services.AddSingleton<ColdChainDispatchService>();

var configuredOrigins = builder.Configuration.GetSection("AllowedOrigins").Get<string[]>() ?? [];
var allowedOrigins = configuredOrigins
    .Append("http://localhost:3000")
    .Append("https://localhost:3000")
    .Where(origin => !string.IsNullOrWhiteSpace(origin))
    .Distinct(StringComparer.OrdinalIgnoreCase)
    .ToArray();

builder.Services.AddCors(options =>
{
    options.AddPolicy("Frontend", policy =>
        policy.WithOrigins(allowedOrigins)
            .AllowAnyHeader()
            .AllowAnyMethod());
});

var app = builder.Build();

app.UseForwardedHeaders();
if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
}

app.UseCors("Frontend");
app.UseAuthorization();
app.MapControllers();
app.MapGet("/healthz", () => Results.Ok(new { status = "healthy", service = "grifols-plasma-supply-api" }));

app.Run();

public partial class Program;
