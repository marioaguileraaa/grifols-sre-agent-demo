import { useEffect, useState } from 'react';
import CheckCircleOutlineIcon from '@mui/icons-material/CheckCircleOutline';
import LocalShippingOutlinedIcon from '@mui/icons-material/LocalShippingOutlined';
import { Alert, Box, Chip, CircularProgress, Divider, Paper, Stack, Typography } from '@mui/material';
import { useParams } from 'react-router-dom';
import { supplyApi } from '../services/api';
import { Shipment } from '../types';

interface ShipmentPageProps {
  initialShipment?: Shipment;
}

export default function ShipmentPage({ initialShipment }: ShipmentPageProps) {
  const { shipmentId = '' } = useParams();
  const [shipment, setShipment] = useState<Shipment | undefined>(
    initialShipment?.id === shipmentId ? initialShipment : undefined,
  );
  const [error, setError] = useState('');

  useEffect(() => {
    if (!shipment) {
      supplyApi.getShipment(shipmentId).then(setShipment).catch(() => setError('Shipment tracking could not be loaded.'));
    }
  }, [shipment, shipmentId]);

  if (error) return <Alert severity="error">{error}</Alert>;
  if (!shipment) return <Box textAlign="center"><CircularProgress aria-label="Loading shipment" /></Box>;

  return (
    <Stack spacing={3}>
      <Alert severity="success" icon={<CheckCircleOutlineIcon />}>
        Dispatch reserved successfully. Synthetic shipment {shipment.id} is ready for tracking.
      </Alert>
      <Box>
        <Typography variant="h2">Shipment tracking</Typography>
        <Typography color="text.secondary">Tracking code {shipment.trackingCode}</Typography>
      </Box>
      <Paper variant="outlined" sx={{ p: { xs: 2, md: 4 } }}>
        <Stack direction={{ xs: 'column', sm: 'row' }} justifyContent="space-between" gap={2}>
          <Box>
            <Typography variant="overline">Destination</Typography>
            <Typography variant="h6">{shipment.destinationFacility}</Typography>
          </Box>
          <Chip color="secondary" icon={<LocalShippingOutlinedIcon />} label={shipment.status} />
        </Stack>
        <Divider sx={{ my: 3 }} />
        <Stack spacing={3}>
          {shipment.trackingMilestones.map((milestone, index) => (
            <Stack key={`${milestone.status}-${index}`} direction="row" spacing={2}>
              <CheckCircleOutlineIcon color={index === 0 ? 'secondary' : 'disabled'} />
              <Box>
                <Typography fontWeight={700}>{milestone.description}</Typography>
                <Typography variant="body2" color="text.secondary">
                  {new Date(milestone.timestamp).toLocaleString()} · {milestone.status}
                </Typography>
              </Box>
            </Stack>
          ))}
        </Stack>
      </Paper>
    </Stack>
  );
}
