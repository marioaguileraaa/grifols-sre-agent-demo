import React, { createContext, useContext, useMemo, useState } from 'react';
import { TherapySupply } from '../types';

export interface SelectedSupply {
  supply: TherapySupply;
  quantity: number;
  handlingNotes: string;
}

interface RequisitionState {
  distributionCenterId: number | null;
  items: SelectedSupply[];
  addSupply: (supply: TherapySupply) => void;
  updateQuantity: (supplyId: number, quantity: number) => void;
  removeSupply: (supplyId: number) => void;
  clear: () => void;
}

const RequisitionContext = createContext<RequisitionState | undefined>(undefined);

export const RequisitionProvider: React.FC<React.PropsWithChildren> = ({ children }) => {
  const [distributionCenterId, setDistributionCenterId] = useState<number | null>(null);
  const [items, setItems] = useState<SelectedSupply[]>([]);

  const value = useMemo<RequisitionState>(() => ({
    distributionCenterId,
    items,
    addSupply: (supply) => {
      if (distributionCenterId !== null && distributionCenterId !== supply.distributionCenterId) {
        setItems([]);
      }
      setDistributionCenterId(supply.distributionCenterId);
      setItems((current) => {
        const existing = current.find((item) => item.supply.id === supply.id);
        return existing
          ? current.map((item) => item.supply.id === supply.id
            ? { ...item, quantity: item.quantity + 1 }
            : item)
          : [...current, { supply, quantity: 1, handlingNotes: '' }];
      });
    },
    updateQuantity: (supplyId, quantity) =>
      setItems((current) => current.map((item) =>
        item.supply.id === supplyId ? { ...item, quantity: Math.max(1, quantity) } : item)),
    removeSupply: (supplyId) =>
      setItems((current) => current.filter((item) => item.supply.id !== supplyId)),
    clear: () => {
      setDistributionCenterId(null);
      setItems([]);
    },
  }), [distributionCenterId, items]);

  return <RequisitionContext.Provider value={value}>{children}</RequisitionContext.Provider>;
};

export function useRequisition(): RequisitionState {
  const context = useContext(RequisitionContext);
  if (!context) {
    throw new Error('useRequisition must be used within RequisitionProvider');
  }
  return context;
}
