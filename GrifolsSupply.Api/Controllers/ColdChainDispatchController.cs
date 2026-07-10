using GrifolsSupply.Api.Models;
using GrifolsSupply.Api.Services;
using Microsoft.AspNetCore.Mvc;

namespace GrifolsSupply.Api.Controllers;

[ApiController]
[Route("api/cold-chain-dispatch")]
public sealed class ColdChainDispatchController(ColdChainDispatchService dispatchService) : ControllerBase
{
    [HttpPost]
    [ProducesResponseType<Shipment>(StatusCodes.Status201Created)]
    [ProducesResponseType<DispatchFailure>(StatusCodes.Status503ServiceUnavailable)]
    public ActionResult<Shipment> Reserve([FromBody] ColdChainDispatchRequest request)
    {
        var correlationId = Request.Headers.TryGetValue("X-Correlation-ID", out var requestedCorrelationId)
            && !string.IsNullOrWhiteSpace(requestedCorrelationId)
                ? requestedCorrelationId.ToString()
                : HttpContext.TraceIdentifier;
        Response.Headers["X-Correlation-ID"] = correlationId;

        var result = dispatchService.Reserve(request, correlationId);
        if (result.ValidationError is not null)
        {
            return BadRequest(new { message = result.ValidationError, correlationId });
        }

        if (result.Failure is not null)
        {
            return StatusCode(StatusCodes.Status503ServiceUnavailable, result.Failure);
        }

        return CreatedAtAction(nameof(GetByTrackingId), new { trackingId = result.Shipment!.TrackingId }, result.Shipment);
    }

    [HttpGet("{trackingId}")]
    public ActionResult<Shipment> GetByTrackingId(string trackingId)
    {
        var shipment = dispatchService.Find(trackingId);
        return shipment is null ? NotFound() : Ok(shipment);
    }
}
