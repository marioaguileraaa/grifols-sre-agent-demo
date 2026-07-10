using GrifolsPlasmaSupply.Api.Models;
using GrifolsPlasmaSupply.Api.Services;
using Microsoft.AspNetCore.Mvc;

namespace GrifolsPlasmaSupply.Api.Controllers;

[ApiController]
[Route("api/distribution-centers")]
public sealed class DistributionCentersController(SyntheticCatalog catalog) : ControllerBase
{
    [HttpGet]
    public ActionResult<IReadOnlyList<DistributionCenter>> GetAll([FromQuery] string? region = null) =>
        Ok(string.IsNullOrWhiteSpace(region)
            ? catalog.DistributionCenters
            : catalog.DistributionCenters.Where(item =>
                item.Region.Contains(region, StringComparison.OrdinalIgnoreCase)));

    [HttpGet("{id}")]
    public ActionResult<DistributionCenter> GetById(string id)
    {
        var center = catalog.FindCenter(id);
        return center is null ? NotFound() : Ok(center);
    }
}
