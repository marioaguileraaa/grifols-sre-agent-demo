import { FormEvent, useState } from 'react';
import AssignmentTurnedInOutlinedIcon from '@mui/icons-material/AssignmentTurnedInOutlined';
import { Alert, Box, Button, Divider, Paper, Stack, TextField, Typography } from '@mui/material';
import { Link as RouterLink, useNavigate } from 'react-router-dom';
import { supplyApi } from '../services/api';
import { ReplenishmentRequisition } from '../types';
import { SelectedSupplies } from './SuppliesPage';

interface RequisitionPageProps {
  selected: SelectedSupplies;
  onCreated: (requisition: ReplenishmentRequisition) => void;
}

export default function RequisitionPage({ selected, onCreated }: RequisitionPageProps) {
  const navigate = useNavigate();
  const [destinationFacility, setDestinationFacility] = useState('Synthetic Hospital Receiving Center');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState('');
  const items = Object.values(selected);

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    if (!items.length) return;
    setSubmitting(true);
    setError('');
    try {
      const created = await supplyApi.createRequisition({
        distributionCenterId: items[0].supply.distributionCenterId,
        destinationFacility,
        lines: items.map(item => ({ therapySupplyId: item.supply.id, quantity: item.quantity })),
      });
      onCreated(created);
      navigate(`/dispatch/${created.id}`);
    } catch {
      setError('The requisition could not be created. Review the synthetic inputs and retry.');
    } finally {
      setSubmitting(false);
    }
  };

  if (!items.length) {
    return (
      <Alert severity="info" action={<Button component={RouterLink} to="/">Browse centers</Button>}>
        Select at least one synthetic therapy supply before preparing a requisition.
      </Alert>
    );
  }

  return (
    <Stack component="form" onSubmit={submit} spacing={3}>
      <Box>
        <Typography variant="h2">Replenishment requisition</Typography>
        <Typography color="text.secondary">Confirm quantities and the synthetic receiving facility.</Typography>
      </Box>
      <Paper variant="outlined" sx={{ p: { xs: 2, md: 3 } }}>
        {items.map((item, index) => (
          <Box key={item.supply.id}>
            {index > 0 && <Divider sx={{ my: 2 }} />}
            <Stack direction="row" justifyContent="space-between" gap={2}>
              <Box>
                <Typography fontWeight={700}>{item.supply.name}</Typography>
                <Typography variant="body2" color="text.secondary">{item.supply.packaging}</Typography>
              </Box>
              <Typography fontWeight={700}>{item.quantity} units</Typography>
            </Stack>
          </Box>
        ))}
      </Paper>
      <TextField
        required
        label="Synthetic destination facility"
        value={destinationFacility}
        onChange={event => setDestinationFacility(event.target.value)}
      />
      {error && <Alert severity="error">{error}</Alert>}
      <Button type="submit" variant="contained" size="large" disabled={submitting} startIcon={<AssignmentTurnedInOutlinedIcon />}>
        {submitting ? 'Creating requisition…' : 'Create requisition'}
      </Button>
    </Stack>
  );
}
