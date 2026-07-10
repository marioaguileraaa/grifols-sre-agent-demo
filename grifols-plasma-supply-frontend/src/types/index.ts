export interface DistributionCenter {
  id: string;
  name: string;
  city: string;
  country: string;
  region: string;
  temperatureCapability: string;
  isOperational: boolean;
}

export interface TherapySupply {
  id: string;
  distributionCenterId: string;
  name: string;
  category: string;
  packaging: string;
  storageRange: string;
  availableUnits: number;
}

export interface RequisitionLine {
  therapySupplyId: string;
  quantity: number;
}

export interface ReplenishmentRequisition {
  id: string;
  distributionCenterId: string;
  destinationFacility: string;
  lines: RequisitionLine[];
  createdAt: string;
  status: string;
}

export interface CreateReplenishmentRequisitionRequest {
  distributionCenterId: string;
  destinationFacility: string;
  lines: RequisitionLine[];
}

export interface DispatchReservationRequest {
  requisitionId: string;
  destinationFacility: string;
  deliveryWindow: string;
  receivingContact: string;
  priority: 'standard' | 'urgent';
  packaging: string;
  dispatchNotes: string;
}

export type ShipmentStatus = 'reserved' | 'prepared' | 'inTransit' | 'delivered';

export interface TrackingMilestone {
  status: ShipmentStatus;
  timestamp: string;
  description: string;
}

export interface Shipment {
  id: string;
  trackingCode: string;
  requisitionId: string;
  distributionCenterId: string;
  destinationFacility: string;
  deliveryWindow: string;
  packaging: string;
  status: ShipmentStatus;
  createdAt: string;
  trackingMilestones: TrackingMilestone[];
}

export interface ApiError {
  code: string;
  message: string;
  correlationId: string;
  timestamp: string;
}
