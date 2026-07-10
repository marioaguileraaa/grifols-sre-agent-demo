import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import App from './App';

const center = {
  id: 'BCN-01',
  name: 'Barcelona Plasma Operations Center',
  city: 'Barcelona',
  country: 'Spain',
  region: 'Southern Europe',
  temperatureCapability: '2–8 °C',
  isOperational: true,
};

const supply = {
  id: 'TS-IMM-100',
  distributionCenterId: 'BCN-01',
  name: 'Synthetic Immune Therapy Supply',
  category: 'Immune support',
  packaging: 'Temperature-controlled case',
  storageRange: '2–8 °C',
  availableUnits: 240,
};

const requisition = {
  id: 'REQ-TEST-001',
  distributionCenterId: 'BCN-01',
  destinationFacility: 'Synthetic Hospital Receiving Center',
  lines: [{ therapySupplyId: supply.id, quantity: 1 }],
  createdAt: '2026-07-10T10:00:00Z',
  status: 'Pending dispatch reservation',
};

const shipment = {
  id: 'SHP-TEST-001',
  trackingCode: 'GPS-TEST-001',
  requisitionId: requisition.id,
  distributionCenterId: 'BCN-01',
  destinationFacility: requisition.destinationFacility,
  deliveryWindow: 'Next validated 4-hour window',
  packaging: supply.packaging,
  status: 'reserved',
  createdAt: '2026-07-10T10:01:00Z',
  trackingMilestones: [{
    status: 'reserved',
    timestamp: '2026-07-10T10:01:00Z',
    description: 'Cold-chain dispatch capacity reserved',
  }],
};

function jsonResponse(body: unknown, status = 200): Response {
  return {
    ok: status >= 200 && status < 300,
    status,
    headers: new Headers(),
    json: async () => body,
  } as Response;
}

beforeEach(() => {
  window.history.pushState({}, '', '/');
  global.fetch = jest.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = input.toString();
    if (url === '/api/distribution-centers') return jsonResponse([center]);
    if (url === '/api/distribution-centers/BCN-01') return jsonResponse(center);
    if (url.startsWith('/api/therapy-supplies')) return jsonResponse([supply]);
    if (url === '/api/requisitions' && init?.method === 'POST') return jsonResponse(requisition, 201);
    if (url === '/api/dispatch-reservations' && init?.method === 'POST') return jsonResponse(shipment, 201);
    throw new Error(`Unexpected request: ${url}`);
  }) as jest.Mock;
});

test('renders branding and the persistent synthetic-data disclaimer', async () => {
  render(<App />);
  expect(screen.getByText('Grifols Plasma Supply')).toBeInTheDocument();
  expect(screen.getByRole('note')).toHaveTextContent(/fictional and unofficial demonstration/i);
  expect(await screen.findByText(center.name)).toBeInTheDocument();
});

test('completes the center-to-shipment critical flow', async () => {
  render(<App />);

  fireEvent.click(await screen.findByRole('link', { name: `Browse supplies from ${center.name}` }));
  fireEvent.click(await screen.findByRole('button', { name: `Add ${supply.name} to requisition` }));
  fireEvent.click(screen.getAllByRole('link', { name: /review requisition/i })[0]);
  fireEvent.click(await screen.findByRole('button', { name: 'Create requisition' }));

  expect(await screen.findByText(/cold-chain dispatch reservation/i)).toBeInTheDocument();
  fireEvent.click(screen.getByRole('button', { name: 'Reserve dispatch' }));

  expect(await screen.findByText(/shipment tracking/i)).toBeInTheDocument();
  expect(screen.getByText(new RegExp(shipment.trackingCode))).toBeInTheDocument();
  await waitFor(() => expect(global.fetch).toHaveBeenCalledWith(
    '/api/dispatch-reservations',
    expect.objectContaining({ method: 'POST' }),
  ));
});
