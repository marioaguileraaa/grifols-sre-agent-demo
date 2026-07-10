using GrifolsSupply.Api.Models;
using GrifolsSupply.Api.Services;
using Microsoft.AspNetCore.Mvc;

namespace GrifolsSupply.Api.Controllers;

[ApiController]
[Route("api/distribution-centers")]
public sealed class DistributionCentersController : ControllerBase
{
    [HttpGet]
    public ActionResult<IEnumerable<DistributionCenter>> GetAll() =>
        Ok(SyntheticCatalog.DistributionCenters);

    [HttpGet("{id:int}")]
    public ActionResult<DistributionCenter> GetById(int id)
    {
        var center = SyntheticCatalog.DistributionCenters.SingleOrDefault(item => item.Id == id);
        return center is null ? NotFound() : Ok(center);
    }

    [HttpGet("search")]
    public ActionResult<IEnumerable<DistributionCenter>> Search([FromQuery] string? query)
    {
        if (string.IsNullOrWhiteSpace(query))
        {
            return Ok(SyntheticCatalog.DistributionCenters);
        }

        return Ok(SyntheticCatalog.DistributionCenters.Where(center =>
            center.Name.Contains(query, StringComparison.OrdinalIgnoreCase) ||
            center.Region.Contains(query, StringComparison.OrdinalIgnoreCase) ||
            center.Description.Contains(query, StringComparison.OrdinalIgnoreCase)));
    }
}
