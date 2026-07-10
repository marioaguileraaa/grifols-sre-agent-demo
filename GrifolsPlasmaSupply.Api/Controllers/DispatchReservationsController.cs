using GrifolsPlasmaSupply.Api.Middleware;
using GrifolsPlasmaSupply.Api.Models;
using GrifolsPlasmaSupply.Api.Services;
using Microsoft.AspNetCore.Mvc;

namespace GrifolsPlasmaSupply.Api.Controllers;

[ApiController]
[Route("api/dispatch-reservations")]
public sealed class DispatchReservationsController(
    ColdChainReservationService reservationService,
    DemoSupplyStore store) : ControllerBase
{
    [HttpPost]
    public ActionResult<Shipment> Reserve(DispatchReservationRequest request)
    {
        var correlationId = HttpContext.Items[CorrelationIdMiddleware.ItemName]?.ToString()
            ?? Guid.NewGuid().ToString("N");
        var requisition = store.GetRequisition(request.RequisitionId);
        if (requisition is null)
        {
            return NotFound(new ApiError(
                "REQUISITION_NOT_FOUND",
                "The replenishment requisition was not found.",
                correlationId,
                DateTimeOffset.UtcNow));
        }

        if (!requisition.DestinationFacility.Equals(request.DestinationFacility, StringComparison.OrdinalIgnoreCase))
        {
            ModelState.AddModelError(nameof(request.DestinationFacility), "Destination facility must match the requisition.");
            return ValidationProblem(ModelState);
        }

        var result = reservationService.Reserve(request, correlationId);
        if (!result.Success)
        {
            return StatusCode(StatusCodes.Status503ServiceUnavailable, new ApiError(
                ColdChainReservationService.FailureCode,
                "Cold-chain dispatch capacity is temporarily unavailable. Retry the requisition after recovery.",
                correlationId,
                DateTimeOffset.UtcNow));
        }

        return CreatedAtAction(
            nameof(ShipmentsController.GetById),
            "Shipments",
            new { id = result.Shipment!.Id },
            result.Shipment);
    }
}
