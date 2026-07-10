using System.Collections.Concurrent;
using GrifolsSupply.Api.Models;
using GrifolsSupply.Api.Services;
using Microsoft.AspNetCore.Mvc;

namespace GrifolsSupply.Api.Controllers;

[ApiController]
[Route("api/requisitions")]
public sealed class RequisitionsController : ControllerBase
{
    private static readonly ConcurrentDictionary<string, Requisition> Requisitions = new();

    [HttpPost]
    public ActionResult<Requisition> Create([FromBody] CreateRequisitionRequest request)
    {
        if (SyntheticCatalog.DistributionCenters.All(center => center.Id != request.DistributionCenterId))
        {
            return BadRequest(new { message = "Unknown synthetic distribution center." });
        }

        var items = new List<RequisitionItem>();
        foreach (var line in request.Items)
        {
            var supply = SyntheticCatalog.TherapySupplies.SingleOrDefault(item =>
                item.Id == line.TherapySupplyId &&
                item.DistributionCenterId == request.DistributionCenterId);
            if (supply is null)
            {
                return BadRequest(new { message = $"Therapy supply {line.TherapySupplyId} is not available at this center." });
            }

            items.Add(new RequisitionItem
            {
                TherapySupplyId = supply.Id,
                TherapySupply = supply,
                Quantity = line.Quantity,
                HandlingNotes = line.HandlingNotes
            });
        }

        var requisition = new Requisition
        {
            Id = $"REQ-{DateTimeOffset.UtcNow:yyyyMMdd}-{Guid.NewGuid():N}"[..22].ToUpperInvariant(),
            RequestingFacility = request.RequestingFacility,
            DistributionCenterId = request.DistributionCenterId,
            Items = items,
            Status = "ReadyForDispatch"
        };
        Requisitions[requisition.Id] = requisition;
        return CreatedAtAction(nameof(GetById), new { id = requisition.Id }, requisition);
    }

    [HttpGet("{id}")]
    public ActionResult<Requisition> GetById(string id) =>
        Requisitions.TryGetValue(id, out var requisition) ? Ok(requisition) : NotFound();
}
