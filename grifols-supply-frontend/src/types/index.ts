export interface DistributionCenter {
  id: number;
  code: string;
  name: string;
  description: string;
  region: string;
  address: string;
  serviceWindow: string;
  coldChainRange: string;
  isOperational: boolean;
}

export interface TherapySupply {
  id: number;
  sku: string;
  name: string;
  description: string;
  category: string;
  unitOfMeasure: string;
  availableUnits: number;
  distributionCenterId: number;
  isAvailable: boolean;
}

export interface RequisitionLine {
  therapySupplyId: number;
  quantity: number;
  handlingNotes: string;
}

export interface Requisition {
  id: string;
  requestingFacility: string;
  distributionCenterId: number;
  items: Array<{
    therapySupplyId: number;
    therapySupply: TherapySupply;
    quantity: number;
    handlingNotes: string;
  }>;
  createdAt: string;
  status: string;
}

export enum ShipmentStatus {
  DispatchReserved = 1,
  ColdChainPrepared = 2,
  InTransit = 3,
  Delivered = 4,
  Cancelled = 5,
}

export interface Shipment {
  id: string;
  trackingId: string;
  requisitionId: string;
  distributionCenterId: number;
  distributionCenterName: string;
  destinationFacility: string;
  correlationId: string;
  status: ShipmentStatus;
  reservedAt: string;
  estimatedArrival: string;
}

export interface DispatchFailure {
  code: string;
  message: string;
  correlationId: string;
  timestamp: string;
}
