using GrifolsPlasmaSupply.Api.Models;
using GrifolsPlasmaSupply.Api.Services;
using Microsoft.AspNetCore.Mvc;

namespace GrifolsPlasmaSupply.Api.Controllers;

[ApiController]
[Route("api/requisitions")]
public sealed class RequisitionsController(DemoSupplyStore store, SyntheticCatalog catalog) : ControllerBase
{
    [HttpGet]
    public ActionResult<IReadOnlyCollection<ReplenishmentRequisition>> GetAll() =>
        Ok(store.GetRequisitions());

    [HttpGet("{id}")]
    public ActionResult<ReplenishmentRequisition> GetById(string id)
    {
        var requisition = store.GetRequisition(id);
        return requisition is null ? NotFound() : Ok(requisition);
    }

    [HttpPost]
    public ActionResult<ReplenishmentRequisition> Create(CreateReplenishmentRequisitionRequest request)
    {
        if (catalog.FindCenter(request.DistributionCenterId) is null)
        {
            ModelState.AddModelError(nameof(request.DistributionCenterId), "Unknown distribution center.");
        }

        if (request.Lines.Count == 0)
        {
            ModelState.AddModelError(nameof(request.Lines), "At least one requisition line is required.");
        }

        foreach (var line in request.Lines)
        {
            var supply = catalog.FindSupply(line.TherapySupplyId);
            if (supply is null || !supply.DistributionCenterId.Equals(request.DistributionCenterId, StringComparison.OrdinalIgnoreCase))
            {
                ModelState.AddModelError(nameof(request.Lines), $"Supply {line.TherapySupplyId} is not available at the selected center.");
            }
            else if (line.Quantity > supply.AvailableUnits)
            {
                ModelState.AddModelError(nameof(request.Lines), $"Requested quantity for {line.TherapySupplyId} exceeds synthetic availability.");
            }
        }

        if (!ModelState.IsValid)
        {
            return ValidationProblem(ModelState);
        }

        var requisition = store.AddRequisition(request);
        return CreatedAtAction(nameof(GetById), new { id = requisition.Id }, requisition);
    }
}
