using GrifolsPlasmaSupply.Api.Models;
using GrifolsPlasmaSupply.Api.Services;
using Microsoft.AspNetCore.Mvc;

namespace GrifolsPlasmaSupply.Api.Controllers;

[ApiController]
[Route("api/shipments")]
public sealed class ShipmentsController(DemoSupplyStore store) : ControllerBase
{
    [HttpGet]
    public ActionResult<IReadOnlyCollection<Shipment>> GetAll() => Ok(store.GetShipments());

    [HttpGet("{id}")]
    public ActionResult<Shipment> GetById(string id)
    {
        var shipment = store.GetShipment(id);
        return shipment is null ? NotFound() : Ok(shipment);
    }
}
