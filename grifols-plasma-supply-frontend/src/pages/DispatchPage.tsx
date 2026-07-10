import { FormEvent, useState } from 'react';
import AcUnitIcon from '@mui/icons-material/AcUnit';
import LocalShippingOutlinedIcon from '@mui/icons-material/LocalShippingOutlined';
import { Alert, Box, Button, MenuItem, Paper, Stack, TextField, Typography } from '@mui/material';
import { useNavigate, useParams } from 'react-router-dom';
import { ApiClientError, supplyApi } from '../services/api';
import { ReplenishmentRequisition, Shipment } from '../types';

interface DispatchPageProps {
  requisition?: ReplenishmentRequisition;
  onReserved: (shipment: Shipment) => void;
}

export default function DispatchPage({ requisition, onReserved }: DispatchPageProps) {
  const { requisitionId = '' } = useParams();
  const navigate = useNavigate();
  const [deliveryWindow, setDeliveryWindow] = useState('Next validated 4-hour window');
  const [receivingContact, setReceivingContact] = useState('Synthetic Logistics Desk');
  const [priority, setPriority] = useState<'standard' | 'urgent'>('urgent');
  const [packaging, setPackaging] = useState('Temperature-controlled case');
  const [dispatchNotes, setDispatchNotes] = useState('Synthetic SRE demonstration dispatch');
  const [submitting, setSubmitting] = useState(false);
  const [failure, setFailure] = useState<ApiClientError>();

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    if (!requisition) return;
    setSubmitting(true);
    setFailure(undefined);
    try {
      const shipment = await supplyApi.reserveDispatch({
        requisitionId,
        destinationFacility: requisition.destinationFacility,
        deliveryWindow,
        receivingContact,
        priority,
        packaging,
        dispatchNotes,
      });
      onReserved(shipment);
      navigate(`/shipments/${shipment.id}`);
    } catch (error) {
      setFailure(error instanceof ApiClientError
        ? error
        : new ApiClientError(0, 'NETWORK_ERROR', 'The dispatch reservation service could not be reached.'));
    } finally {
      setSubmitting(false);
    }
  };

  if (!requisition || requisition.id !== requisitionId) {
    return <Alert severity="warning">This requisition is not available in the current browser session. Return to the network and create a new one.</Alert>;
  }

  return (
    <Stack component="form" onSubmit={submit} spacing={3}>
      <Box>
        <Typography variant="h2">Cold-chain dispatch reservation</Typography>
        <Typography color="text.secondary">Requisition {requisition.id} · {requisition.destinationFacility}</Typography>
      </Box>
      <Paper variant="outlined" sx={{ p: { xs: 2, md: 3 } }}>
        <Stack spacing={3}>
          <TextField required label="Delivery window" value={deliveryWindow} onChange={event => setDeliveryWindow(event.target.value)} />
          <TextField required label="Synthetic receiving contact" value={receivingContact} onChange={event => setReceivingContact(event.target.value)} />
          <TextField select label="Priority" value={priority} onChange={event => setPriority(event.target.value as 'standard' | 'urgent')}>
            <MenuItem value="standard">Standard</MenuItem>
            <MenuItem value="urgent">Urgent</MenuItem>
          </TextField>
          <TextField required label="Cold-chain packaging" value={packaging} onChange={event => setPackaging(event.target.value)} />
          <TextField label="Dispatch notes" multiline minRows={2} value={dispatchNotes} onChange={event => setDispatchNotes(event.target.value)} />
        </Stack>
      </Paper>
      {failure && (
        <Alert severity="error" icon={<AcUnitIcon />} aria-live="assertive">
          <Typography fontWeight={700}>{failure.code}</Typography>
          <Typography>{failure.message}</Typography>
          {failure.correlationId && <Typography variant="body2">Correlation ID: {failure.correlationId}</Typography>}
          <Typography variant="body2">The requisition remains available for retry.</Typography>
        </Alert>
      )}
      <Button type="submit" variant="contained" size="large" disabled={submitting} startIcon={<LocalShippingOutlinedIcon />}>
        {submitting ? 'Reserving dispatch…' : failure ? 'Retry reservation' : 'Reserve dispatch'}
      </Button>
    </Stack>
  );
}
