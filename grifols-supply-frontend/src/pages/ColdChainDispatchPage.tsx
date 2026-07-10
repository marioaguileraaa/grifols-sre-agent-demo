import React, { useState } from 'react';
import {
  Alert,
  Box,
  Button,
  Card,
  CardContent,
  CircularProgress,
  Step,
  StepLabel,
  Stepper,
  TextField,
  Typography,
} from '@mui/material';
import { AcUnit } from '@mui/icons-material';
import { useNavigate } from 'react-router-dom';
import { coldChainDispatchService, isDispatchFailure, requisitionService } from '../services/api';
import { useRequisition } from '../state/RequisitionContext';

const steps = ['Facility details', 'Review synthetic request', 'Reserve cold-chain dispatch'];

const ColdChainDispatchPage: React.FC = () => {
  const navigate = useNavigate();
  const { distributionCenterId, items, clear } = useRequisition();
  const [destinationFacility, setDestinationFacility] = useState('Synthetic University Hospital');
  const [requestedBy, setRequestedBy] = useState('Demo Supply Coordinator');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState('');
  const [correlationId, setCorrelationId] = useState('');

  if (items.length === 0 || distributionCenterId === null) {
    return (
      <Alert severity="info" action={<Button onClick={() => navigate('/')}>Browse centers</Button>}>
        Add synthetic therapy supplies before reserving a dispatch.
      </Alert>
    );
  }

  const reserveDispatch = async () => {
    const lines = items.map((item) => ({
      therapySupplyId: item.supply.id,
      quantity: item.quantity,
      handlingNotes: item.handlingNotes,
    }));

    setSubmitting(true);
    setError('');
    setCorrelationId('');
    try {
      const requisition = await requisitionService.create({
        requestingFacility: destinationFacility,
        distributionCenterId,
        items: lines,
      });
      const shipment = await coldChainDispatchService.reserve({
        requisitionId: requisition.id,
        distributionCenterId,
        destinationFacility,
        requestedBy,
        items: lines,
      });
      clear();
      navigate(`/shipments/${shipment.trackingId}`, { state: shipment });
    } catch (caught) {
      if (isDispatchFailure(caught)) {
        setError(`${caught.details.code}: ${caught.details.message}`);
        setCorrelationId(caught.details.correlationId);
      } else {
        setError(caught instanceof Error ? caught.message : 'Unable to reserve the synthetic dispatch.');
      }
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <>
      <Typography variant="h3" component="h1" gutterBottom>Cold-chain dispatch</Typography>
      <Stepper activeStep={2} sx={{ my: 4 }}>
        {steps.map((step) => <Step key={step}><StepLabel>{step}</StepLabel></Step>)}
      </Stepper>
      <Card variant="outlined" sx={{ maxWidth: 760 }}>
        <CardContent>
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mb: 3 }}>
            <AcUnit color="primary" />
            <Typography variant="h5">Dispatch reservation details</Typography>
          </Box>
          <TextField
            fullWidth
            required
            label="Destination hospital or facility"
            value={destinationFacility}
            onChange={(event) => setDestinationFacility(event.target.value)}
            sx={{ mb: 2 }}
          />
          <TextField
            fullWidth
            required
            label="Requested by"
            value={requestedBy}
            onChange={(event) => setRequestedBy(event.target.value)}
            sx={{ mb: 3 }}
          />
          <Typography color="text.secondary" sx={{ mb: 3 }}>
            {items.length} generic synthetic supply line(s). No patient, clinical, or financial data is collected.
          </Typography>
          {error && (
            <Alert severity="error" sx={{ mb: 3 }}>
              <strong>Dispatch reservation failed.</strong> {error}
              {correlationId && <Box component="span" sx={{ display: 'block', mt: 1 }}>Correlation ID: {correlationId}</Box>}
            </Alert>
          )}
          <Button
            variant="contained"
            size="large"
            disabled={submitting || !destinationFacility.trim() || !requestedBy.trim()}
            onClick={reserveDispatch}
          >
            {submitting ? <CircularProgress size={24} color="inherit" /> : 'Reserve dispatch'}
          </Button>
        </CardContent>
      </Card>
    </>
  );
};

export default ColdChainDispatchPage;
