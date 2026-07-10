import {
  ApiError,
  CreateReplenishmentRequisitionRequest,
  DispatchReservationRequest,
  DistributionCenter,
  ReplenishmentRequisition,
  Shipment,
  TherapySupply,
} from '../types';

const API_BASE_URL = '/api';

export class ApiClientError extends Error {
  constructor(
    public readonly status: number,
    public readonly code: string,
    message: string,
    public readonly correlationId?: string,
  ) {
    super(message);
    this.name = 'ApiClientError';
  }
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`${API_BASE_URL}${path}`, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      ...init?.headers,
    },
  });

  if (response.ok) {
    return response.status === 204 ? (undefined as T) : response.json() as Promise<T>;
  }

  let error: Partial<ApiError> = {};
  try {
    error = await response.json() as ApiError;
  } catch {
    // The fallback below preserves an explicit error even for non-JSON proxy failures.
  }
  throw new ApiClientError(
    response.status,
    error.code ?? 'API_REQUEST_FAILED',
    error.message ?? `Request failed with status ${response.status}.`,
    error.correlationId ?? response.headers.get('X-Correlation-ID') ?? undefined,
  );
}

export const supplyApi = {
  getDistributionCenters: () => request<DistributionCenter[]>('/distribution-centers'),
  getDistributionCenter: (id: string) =>
    request<DistributionCenter>(`/distribution-centers/${encodeURIComponent(id)}`),
  getTherapySupplies: (centerId: string) =>
    request<TherapySupply[]>(`/therapy-supplies?distributionCenterId=${encodeURIComponent(centerId)}`),
  createRequisition: (payload: CreateReplenishmentRequisitionRequest) =>
    request<ReplenishmentRequisition>('/requisitions', {
      method: 'POST',
      body: JSON.stringify(payload),
    }),
  reserveDispatch: (payload: DispatchReservationRequest) =>
    request<Shipment>('/dispatch-reservations', {
      method: 'POST',
      body: JSON.stringify(payload),
    }),
  getShipment: (id: string) =>
    request<Shipment>(`/shipments/${encodeURIComponent(id)}`),
};
