import { useEffect, useState } from 'react';
import AddCircleOutlineIcon from '@mui/icons-material/AddCircleOutline';
import Inventory2OutlinedIcon from '@mui/icons-material/Inventory2Outlined';
import ThermostatIcon from '@mui/icons-material/Thermostat';
import { Alert, Box, Button, Card, CardActions, CardContent, Chip, CircularProgress, Stack, TextField, Typography } from '@mui/material';
import { Link as RouterLink, useParams } from 'react-router-dom';
import { supplyApi } from '../services/api';
import { DistributionCenter, TherapySupply } from '../types';

export type SelectedSupplies = Record<string, { supply: TherapySupply; quantity: number }>;

interface SuppliesPageProps {
  selected: SelectedSupplies;
  onSelectedChange: (selected: SelectedSupplies) => void;
}

export default function SuppliesPage({ selected, onSelectedChange }: SuppliesPageProps) {
  const { centerId = '' } = useParams();
  const [center, setCenter] = useState<DistributionCenter>();
  const [supplies, setSupplies] = useState<TherapySupply[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    Promise.all([supplyApi.getDistributionCenter(centerId), supplyApi.getTherapySupplies(centerId)])
      .then(([centerResult, suppliesResult]) => {
        setCenter(centerResult);
        setSupplies(suppliesResult);
      })
      .catch(() => setError('Synthetic supplies could not be loaded.'))
      .finally(() => setLoading(false));
  }, [centerId]);

  const selectSupply = (supply: TherapySupply) => {
    const sameCenter = Object.fromEntries(
      Object.entries(selected).filter(([, item]) => item.supply.distributionCenterId === centerId),
    );
    onSelectedChange({ ...sameCenter, [supply.id]: selected[supply.id] ?? { supply, quantity: 1 } });
  };

  const updateQuantity = (supply: TherapySupply, quantity: number) => {
    onSelectedChange({ ...selected, [supply.id]: { supply, quantity: Math.max(1, Math.min(quantity, supply.availableUnits)) } });
  };

  if (loading) return <Box textAlign="center"><CircularProgress aria-label="Loading supplies" /></Box>;
  if (error || !center) return <Alert severity="error">{error || 'Distribution center not found.'}</Alert>;

  return (
    <Stack spacing={4}>
      <Box>
        <Chip label={center.region} color="secondary" />
        <Typography variant="h2" sx={{ mt: 2 }}>{center.name}</Typography>
        <Typography color="text.secondary">{center.city}, {center.country} · {center.temperatureCapability}</Typography>
      </Box>
      <Box sx={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(260px, 1fr))', gap: 3 }}>
        {supplies.map(supply => {
          const selectedItem = selected[supply.id];
          return (
            <Card key={supply.id} className="supply-card" variant={selectedItem ? 'elevation' : 'outlined'}>
              <CardContent>
                <Inventory2OutlinedIcon color="primary" fontSize="large" />
                <Typography variant="h5" sx={{ mt: 2 }} fontWeight={700}>{supply.name}</Typography>
                <Typography color="text.secondary" sx={{ my: 1 }}>{supply.category}</Typography>
                <Stack direction="row" spacing={1} sx={{ my: 2, flexWrap: 'wrap' }}>
                  <Chip icon={<ThermostatIcon />} size="small" label={supply.storageRange} />
                  <Chip size="small" variant="outlined" label={`${supply.availableUnits} synthetic units`} />
                </Stack>
                <Typography variant="body2">{supply.packaging}</Typography>
                {selectedItem && (
                  <TextField
                    type="number"
                    label={`Quantity for ${supply.name}`}
                    value={selectedItem.quantity}
                    onChange={event => updateQuantity(supply, Number(event.target.value))}
                    inputProps={{ min: 1, max: supply.availableUnits }}
                    fullWidth
                    sx={{ mt: 2 }}
                  />
                )}
              </CardContent>
              <CardActions>
                <Button
                  startIcon={<AddCircleOutlineIcon />}
                  onClick={() => selectSupply(supply)}
                  disabled={Boolean(selectedItem)}
                  aria-label={`Add ${supply.name} to requisition`}
                >
                  {selectedItem ? 'Selected' : 'Add to requisition'}
                </Button>
              </CardActions>
            </Card>
          );
        })}
      </Box>
      <Box textAlign="right">
        <Button component={RouterLink} to="/requisition" variant="contained" size="large" disabled={!Object.keys(selected).length}>
          Review requisition
        </Button>
      </Box>
    </Stack>
  );
}
