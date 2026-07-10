import React from 'react';
import { BrowserRouter, Route, Routes } from 'react-router-dom';
import { Container, CssBaseline } from '@mui/material';
import { ThemeProvider, createTheme } from '@mui/material/styles';
import Navbar from './components/Navbar';
import ColdChainDispatchPage from './pages/ColdChainDispatchPage';
import DistributionCenterPage from './pages/DistributionCenterPage';
import HomePage from './pages/HomePage';
import RequisitionPage from './pages/RequisitionPage';
import ShipmentTrackingPage from './pages/ShipmentTrackingPage';
import { RequisitionProvider } from './state/RequisitionContext';
import './App.css';

const theme = createTheme({
  palette: {
    primary: { main: '#005a8b', dark: '#003f63', light: '#d9eef7' },
    secondary: { main: '#008b8b', dark: '#006666' },
    background: { default: '#f4f8fa', paper: '#ffffff' },
  },
  shape: { borderRadius: 10 },
  typography: {
    fontFamily: '"Segoe UI", "Helvetica Neue", Arial, sans-serif',
    h1: { fontWeight: 700 },
    h2: { fontWeight: 700 },
    h3: { fontWeight: 650 },
  },
});

export default function App() {
  return (
    <ThemeProvider theme={theme}>
      <CssBaseline />
      <RequisitionProvider>
        <BrowserRouter>
          <Navbar />
          <Container maxWidth="xl" sx={{ py: 4 }}>
            <Routes>
              <Route path="/" element={<HomePage />} />
              <Route path="/distribution-centers/:id" element={<DistributionCenterPage />} />
              <Route path="/requisition" element={<RequisitionPage />} />
              <Route path="/cold-chain-dispatch" element={<ColdChainDispatchPage />} />
              <Route path="/shipments/:trackingId" element={<ShipmentTrackingPage />} />
            </Routes>
          </Container>
        </BrowserRouter>
      </RequisitionProvider>
    </ThemeProvider>
  );
}
