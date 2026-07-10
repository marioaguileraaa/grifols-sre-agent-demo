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

if (builder.Environment.IsDevelopment())
{
    builder.Services.AddCors(options =>
    {
        options.AddPolicy("LocalFrontend", policy =>
            policy.WithOrigins("http://localhost:3000", "https://localhost:3000")
                .AllowAnyHeader()
                .AllowAnyMethod());
    });
}

var app = builder.Build();

app.UseForwardedHeaders();
if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
    app.UseCors("LocalFrontend");
}

app.UseAuthorization();
app.MapControllers();
app.MapGet("/healthz", () => Results.Ok(new { status = "healthy", service = "grifols-plasma-supply-api" }));
app.MapGet("/api/healthz", () => Results.Ok(new { status = "healthy", service = "grifols-plasma-supply-api" }));

app.Run();

public partial class Program;
