import {
  DispatchFailure,
  DistributionCenter,
  Requisition,
  RequisitionLine,
  Shipment,
  TherapySupply,
} from '../types';

const API_BASE_URL = '/api';

export class ApiError<T = unknown> extends Error {
  constructor(
    message: string,
    public readonly status: number,
    public readonly details: T,
  ) {
    super(message);
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
  const body = response.status === 204 ? undefined : await response.json();
  if (!response.ok) {
    throw new ApiError(body?.message || `API request failed (${response.status})`, response.status, body);
  }
  return body as T;
}

export const distributionCenterService = {
  getAll: () => request<DistributionCenter[]>('/distribution-centers'),
  getById: (id: number) => request<DistributionCenter>(`/distribution-centers/${id}`),
};

export const therapySupplyService = {
  getByDistributionCenter: (id: number) =>
    request<TherapySupply[]>(`/therapy-supplies/distribution-center/${id}`),
};

export const requisitionService = {
  create: (payload: {
    requestingFacility: string;
    distributionCenterId: number;
    items: RequisitionLine[];
  }) => request<Requisition>('/requisitions', {
    method: 'POST',
    body: JSON.stringify(payload),
  }),
};

export const coldChainDispatchService = {
  reserve: (payload: {
    requisitionId: string;
    distributionCenterId: number;
    destinationFacility: string;
    requestedBy: string;
    items: RequisitionLine[];
  }) => request<Shipment>('/cold-chain-dispatch', {
    method: 'POST',
    body: JSON.stringify(payload),
  }),
  getByTrackingId: (trackingId: string) =>
    request<Shipment>(`/cold-chain-dispatch/${encodeURIComponent(trackingId)}`),
};

export function isDispatchFailure(error: unknown): error is ApiError<DispatchFailure> {
  return error instanceof ApiError
    && error.status === 503
    && (error.details as DispatchFailure)?.code === 'COLD_CHAIN_GATEWAY_UNAVAILABLE';
}
