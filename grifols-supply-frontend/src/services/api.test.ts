import { coldChainDispatchService, isDispatchFailure } from './api';

const dispatchPayload = {
  requisitionId: 'REQ-TEST',
  distributionCenterId: 1,
  destinationFacility: 'Synthetic Hospital',
  requestedBy: 'Demo Coordinator',
  items: [{ therapySupplyId: 1, quantity: 8, handlingNotes: '' }],
};

test('returns shipment data from a healthy dispatch reservation', async () => {
  global.fetch = jest.fn().mockResolvedValue({
    ok: true,
    status: 201,
    json: async () => ({ trackingId: 'GPS-20260710-TEST' }),
  } as Response);

  const shipment = await coldChainDispatchService.reserve(dispatchPayload);

  expect(shipment.trackingId).toBe('GPS-20260710-TEST');
  expect(global.fetch).toHaveBeenCalledWith(
    expect.stringContaining('/cold-chain-dispatch'),
    expect.objectContaining({ method: 'POST' }),
  );
});

test('preserves stable failure code and correlation id for the UI', async () => {
  global.fetch = jest.fn().mockResolvedValue({
    ok: false,
    status: 503,
    json: async () => ({
      code: 'COLD_CHAIN_GATEWAY_UNAVAILABLE',
      message: 'The synthetic cold-chain reservation gateway is temporarily unavailable.',
      correlationId: 'corr-demo-503',
    }),
  } as Response);

  try {
    await coldChainDispatchService.reserve(dispatchPayload);
    throw new Error('Expected dispatch reservation to fail');
  } catch (error) {
    expect(isDispatchFailure(error)).toBe(true);
    if (isDispatchFailure(error)) {
      expect(error.details.correlationId).toBe('corr-demo-503');
    }
  }
});
