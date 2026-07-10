import { useState } from 'react';
import { BrowserRouter, Route, Routes } from 'react-router-dom';
import { ThemeProvider, createTheme } from '@mui/material/styles';
import CssBaseline from '@mui/material/CssBaseline';
import { Box, Container } from '@mui/material';
import AppHeader from './components/AppHeader';
import DemoDisclaimer from './components/DemoDisclaimer';
import CentersPage from './pages/CentersPage';
import SuppliesPage from './pages/SuppliesPage';
import RequisitionPage from './pages/RequisitionPage';
import DispatchPage from './pages/DispatchPage';
import ShipmentPage from './pages/ShipmentPage';
import { ReplenishmentRequisition, Shipment, TherapySupply } from './types';
import './App.css';

const theme = createTheme({
  palette: {
    primary: {
      main: '#005EB8',
      light: '#4D8DCE',
      dark: '#003B73',
    },
    secondary: {
      main: '#008C95',
      light: '#47B7BD',
      dark: '#00636A',
    },
    background: {
      default: '#F4FAFC',
      paper: '#FFFFFF',
    },
  },
  typography: {
    fontFamily: '"Inter", "Segoe UI", "Helvetica", "Arial", sans-serif',
    h1: {
      fontSize: 'clamp(2rem, 5vw, 3.5rem)',
      fontWeight: 700,
    },
    h2: {
      fontSize: 'clamp(1.75rem, 4vw, 2.5rem)',
      fontWeight: 600,
    },
    h3: {
      fontSize: '2rem',
      fontWeight: 600,
    },
  },
  shape: {
    borderRadius: 12,
  },
});

function App() {
  const [selectedSupplies, setSelectedSupplies] = useState<Record<string, { supply: TherapySupply; quantity: number }>>({});
  const [requisition, setRequisition] = useState<ReplenishmentRequisition>();
  const [shipment, setShipment] = useState<Shipment>();

  return (
    <ThemeProvider theme={theme}>
      <CssBaseline />
      <BrowserRouter future={{ v7_startTransition: true, v7_relativeSplatPath: true }}>
        <Box className="app-shell">
          <AppHeader selectedCount={Object.keys(selectedSupplies).length} />
          <Container component="main" maxWidth="lg" sx={{ py: { xs: 3, md: 5 }, flex: 1 }}>
            <Routes>
              <Route path="/" element={<CentersPage />} />
              <Route
                path="/centers/:centerId"
                element={<SuppliesPage selected={selectedSupplies} onSelectedChange={setSelectedSupplies} />}
              />
              <Route
                path="/requisition"
                element={<RequisitionPage selected={selectedSupplies} onCreated={setRequisition} />}
              />
              <Route
                path="/dispatch/:requisitionId"
                element={<DispatchPage requisition={requisition} onReserved={setShipment} />}
              />
              <Route path="/shipments/:shipmentId" element={<ShipmentPage initialShipment={shipment} />} />
            </Routes>
          </Container>
          <DemoDisclaimer />
        </Box>
      </BrowserRouter>
    </ThemeProvider>
  );
}

export default App;
