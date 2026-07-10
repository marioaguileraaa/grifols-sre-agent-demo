using GrifolsPlasmaSupply.Api.Models;
using GrifolsPlasmaSupply.Api.Services;
using Microsoft.AspNetCore.Mvc;

namespace GrifolsPlasmaSupply.Api.Controllers;

[ApiController]
[Route("api/therapy-supplies")]
public sealed class TherapySuppliesController(SyntheticCatalog catalog) : ControllerBase
{
    [HttpGet]
    public ActionResult<IEnumerable<TherapySupply>> GetAll(
        [FromQuery] string? distributionCenterId = null,
        [FromQuery] string? search = null)
    {
        var supplies = catalog.TherapySupplies.AsEnumerable();
        if (!string.IsNullOrWhiteSpace(distributionCenterId))
        {
            supplies = supplies.Where(item =>
                item.DistributionCenterId.Equals(distributionCenterId, StringComparison.OrdinalIgnoreCase));
        }
        if (!string.IsNullOrWhiteSpace(search))
        {
            supplies = supplies.Where(item =>
                item.Name.Contains(search, StringComparison.OrdinalIgnoreCase)
                || item.Category.Contains(search, StringComparison.OrdinalIgnoreCase));
        }
        return Ok(supplies);
    }

    [HttpGet("{id}")]
    public ActionResult<TherapySupply> GetById(string id)
    {
        var supply = catalog.FindSupply(id);
        return supply is null ? NotFound() : Ok(supply);
    }
}
