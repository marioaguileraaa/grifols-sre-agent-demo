import React from 'react';
import { render, screen } from '@testing-library/react';
import App from './App';

beforeEach(() => {
  global.fetch = jest.fn().mockResolvedValue({
    ok: true,
    status: 200,
    json: async () => [{
      id: 1,
      code: 'BCN-POC',
      name: 'Barcelona Plasma Operations Center',
      description: 'Fictional center',
      region: 'Southern Europe',
      address: 'Synthetic Campus',
      serviceWindow: 'Demo window',
      coldChainRange: '2-8 C',
      isOperational: true,
    }],
  } as Response);
});

test('renders fictional disclaimer and distribution-center flow', async () => {
  render(<App />);

  expect(screen.getByText(/not an official Grifols system/i)).toBeInTheDocument();
  expect(await screen.findByText('Barcelona Plasma Operations Center')).toBeInTheDocument();
  expect(screen.getByRole('button', { name: /select supplies/i })).toBeInTheDocument();
});
