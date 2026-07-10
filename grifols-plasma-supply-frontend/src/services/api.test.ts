import { ApiClientError, supplyApi } from './api';

function response(body: unknown, status: number, headers?: Record<string, string>): Response {
  return {
    ok: status >= 200 && status < 300,
    status,
    headers: new Headers(headers),
    json: async () => body,
  } as Response;
}

afterEach(() => jest.restoreAllMocks());

test('typed client returns a successful shipment', async () => {
  const shipment = { id: 'SHP-001', trackingCode: 'GPS-001', trackingMilestones: [] };
  global.fetch = jest.fn().mockResolvedValue(response(shipment, 201));

  await expect(supplyApi.reserveDispatch({
    requisitionId: 'REQ-001',
    destinationFacility: 'Synthetic Facility',
    deliveryWindow: 'Synthetic window',
    receivingContact: 'Synthetic Desk',
    priority: 'standard',
    packaging: 'Temperature-controlled case',
    dispatchNotes: '',
  })).resolves.toEqual(shipment);
});

test('typed client propagates structured 503 details', async () => {
  global.fetch = jest.fn().mockResolvedValue(response({
    code: 'COLD_CHAIN_GATEWAY_UNAVAILABLE',
    message: 'Cold-chain dispatch capacity is temporarily unavailable.',
    correlationId: 'corr-503',
    timestamp: '2026-07-10T10:00:00Z',
  }, 503, { 'X-Correlation-ID': 'corr-503' }));

  try {
    await supplyApi.reserveDispatch({
      requisitionId: 'REQ-001',
      destinationFacility: 'Synthetic Facility',
      deliveryWindow: 'Synthetic window',
      receivingContact: 'Synthetic Desk',
      priority: 'urgent',
      packaging: 'Temperature-controlled case',
      dispatchNotes: '',
    });
    throw new Error('Expected request to fail.');
  } catch (error) {
    expect(error).toBeInstanceOf(ApiClientError);
    expect(error).toMatchObject({
      status: 503,
      code: 'COLD_CHAIN_GATEWAY_UNAVAILABLE',
      correlationId: 'corr-503',
    });
  }
});
