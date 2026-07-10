using System.Collections.Concurrent;
using GrifolsPlasmaSupply.Api.Models;

namespace GrifolsPlasmaSupply.Api.Services;

public sealed class DemoSupplyStore
{
    private const int MaximumEntries = 500;
    private readonly ConcurrentDictionary<string, ReplenishmentRequisition> _requisitions = new();
    private readonly ConcurrentDictionary<string, Shipment> _shipments = new();

    public ReplenishmentRequisition AddRequisition(CreateReplenishmentRequisitionRequest request)
    {
        var id = $"REQ-{Guid.NewGuid():N}"[..16].ToUpperInvariant();
        var requisition = new ReplenishmentRequisition(
            id,
            request.DistributionCenterId,
            request.DestinationFacility,
            request.Lines.ToArray(),
            DateTimeOffset.UtcNow,
            "Pending dispatch reservation");
        _requisitions[id] = requisition;
        TrimOldest(_requisitions, item => item.CreatedAt);
        return requisition;
    }

    public ReplenishmentRequisition? GetRequisition(string id) =>
        _requisitions.GetValueOrDefault(id);

    public IReadOnlyCollection<ReplenishmentRequisition> GetRequisitions() =>
        _requisitions.Values.OrderByDescending(item => item.CreatedAt).ToArray();

    public Shipment AddShipment(Shipment shipment)
    {
        _shipments[shipment.Id] = shipment;
        TrimOldest(_shipments, item => item.CreatedAt);
        return shipment;
    }

    public Shipment? GetShipment(string id) => _shipments.GetValueOrDefault(id);

    public IReadOnlyCollection<Shipment> GetShipments() =>
        _shipments.Values.OrderByDescending(item => item.CreatedAt).ToArray();

    private static void TrimOldest<T>(
        ConcurrentDictionary<string, T> entries,
        Func<T, DateTimeOffset> createdAt)
    {
        while (entries.Count > MaximumEntries)
        {
            var oldest = entries.MinBy(item => createdAt(item.Value));
            if (oldest.Key is null || !entries.TryRemove(oldest.Key, out _))
            {
                break;
            }
        }
    }
}
