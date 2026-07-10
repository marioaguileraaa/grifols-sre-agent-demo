import React, { useEffect, useState } from 'react';
import { Alert, Box, Button, Card, CardContent, CircularProgress, Step, StepLabel, Stepper, Typography } from '@mui/material';
import { useLocation, useNavigate, useParams } from 'react-router-dom';
import { coldChainDispatchService } from '../services/api';
import { Shipment, ShipmentStatus } from '../types';

const trackingSteps = [
  { label: 'Dispatch reserved', status: ShipmentStatus.DispatchReserved },
  { label: 'Cold-chain prepared', status: ShipmentStatus.ColdChainPrepared },
  { label: 'In transit', status: ShipmentStatus.InTransit },
  { label: 'Delivered', status: ShipmentStatus.Delivered },
];

const ShipmentTrackingPage: React.FC = () => {
  const { trackingId = '' } = useParams();
  const location = useLocation();
  const navigate = useNavigate();
  const [shipment, setShipment] = useState<Shipment | undefined>(location.state as Shipment | undefined);
  const [error, setError] = useState('');

  useEffect(() => {
    if (!shipment && trackingId) {
      coldChainDispatchService.getByTrackingId(trackingId).then(setShipment).catch(() =>
        setError('Synthetic shipment tracking record not found.'));
    }
  }, [shipment, trackingId]);

  if (error) return <Alert severity="error">{error}</Alert>;
  if (!shipment) return <CircularProgress aria-label="Loading shipment" />;

  const activeStep = Math.max(0, trackingSteps.findIndex((step) => step.status === shipment.status));
  return (
    <>
      <Typography variant="h3" component="h1" gutterBottom>Shipment tracking</Typography>
      <Card variant="outlined" sx={{ maxWidth: 900 }}>
        <CardContent>
          <Typography variant="h5">{shipment.trackingId}</Typography>
          <Typography color="text.secondary">Shipment {shipment.id} · Requisition {shipment.requisitionId}</Typography>
          <Stepper activeStep={activeStep} sx={{ my: 5 }}>
            {trackingSteps.map((step) => <Step key={step.label}><StepLabel>{step.label}</StepLabel></Step>)}
          </Stepper>
          <Box className="tracking-details">
            <Typography><strong>Origin:</strong> {shipment.distributionCenterName}</Typography>
            <Typography><strong>Destination:</strong> {shipment.destinationFacility}</Typography>
            <Typography><strong>Estimated arrival:</strong> {new Date(shipment.estimatedArrival).toLocaleString()}</Typography>
            <Typography><strong>Correlation ID:</strong> {shipment.correlationId}</Typography>
          </Box>
          <Alert severity="info" sx={{ mt: 3 }}>
            All shipment, facility, timing, and tracking details shown here are synthetic demo data.
          </Alert>
        </CardContent>
      </Card>
      <Button sx={{ mt: 3 }} onClick={() => navigate('/')}>Start another synthetic requisition</Button>
    </>
  );
};

export default ShipmentTrackingPage;
