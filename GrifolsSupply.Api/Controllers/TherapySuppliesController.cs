using GrifolsSupply.Api.Models;
using GrifolsSupply.Api.Services;
using Microsoft.AspNetCore.Mvc;

namespace GrifolsSupply.Api.Controllers;

[ApiController]
[Route("api/therapy-supplies")]
public sealed class TherapySuppliesController : ControllerBase
{
    [HttpGet]
    public ActionResult<IEnumerable<TherapySupply>> GetAll() =>
        Ok(SyntheticCatalog.TherapySupplies);

    [HttpGet("{id:int}")]
    public ActionResult<TherapySupply> GetById(int id)
    {
        var supply = SyntheticCatalog.TherapySupplies.SingleOrDefault(item => item.Id == id);
        return supply is null ? NotFound() : Ok(supply);
    }

    [HttpGet("distribution-center/{distributionCenterId:int}")]
    public ActionResult<IEnumerable<TherapySupply>> GetByDistributionCenter(int distributionCenterId) =>
        Ok(SyntheticCatalog.TherapySupplies.Where(item => item.DistributionCenterId == distributionCenterId));

    [HttpGet("category/{category}")]
    public ActionResult<IEnumerable<TherapySupply>> GetByCategory(string category) =>
        Ok(SyntheticCatalog.TherapySupplies.Where(item =>
            item.Category.Equals(category, StringComparison.OrdinalIgnoreCase)));
}
