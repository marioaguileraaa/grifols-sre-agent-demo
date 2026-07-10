import React, { useEffect, useState } from 'react';
import { Alert, Box, Button, Card, CardActions, CardContent, Chip, CircularProgress, Typography } from '@mui/material';
import { AddCircleOutline, ArrowBack } from '@mui/icons-material';
import { useNavigate, useParams } from 'react-router-dom';
import { DistributionCenter, TherapySupply } from '../types';
import { distributionCenterService, therapySupplyService } from '../services/api';
import { useRequisition } from '../state/RequisitionContext';

const DistributionCenterPage: React.FC = () => {
  const { id } = useParams();
  const centerId = Number(id);
  const navigate = useNavigate();
  const { addSupply, items } = useRequisition();
  const [center, setCenter] = useState<DistributionCenter>();
  const [supplies, setSupplies] = useState<TherapySupply[]>([]);
  const [error, setError] = useState('');

  useEffect(() => {
    Promise.all([
      distributionCenterService.getById(centerId),
      therapySupplyService.getByDistributionCenter(centerId),
    ]).then(([centerData, supplyData]) => {
      setCenter(centerData);
      setSupplies(supplyData);
    }).catch(() => setError('Unable to load this synthetic distribution center.'));
  }, [centerId]);

  if (error) return <Alert severity="error">{error}</Alert>;
  if (!center) return <CircularProgress aria-label="Loading supplies" />;

  return (
    <>
      <Button startIcon={<ArrowBack />} onClick={() => navigate('/')}>All centers</Button>
      <Box sx={{ my: 3 }}>
        <Typography variant="h3" component="h1">{center.name}</Typography>
        <Typography color="text.secondary" sx={{ mt: 1 }}>{center.description}</Typography>
        <Chip label={`${center.coldChainRange} validated demo lane`} color="secondary" sx={{ mt: 2 }} />
      </Box>

      <Typography variant="h4" gutterBottom>Generic synthetic therapy supplies</Typography>
      <Alert severity="warning" sx={{ mb: 3 }}>
        Inventory names and quantities are synthetic. This catalog provides no medical or clinical guidance.
      </Alert>
      <Box className="card-grid">
        {supplies.map((supply) => (
          <Card key={supply.id} variant="outlined">
            <CardContent>
              <Chip label={supply.category} size="small" />
              <Typography variant="h6" sx={{ mt: 2 }}>{supply.name}</Typography>
              <Typography color="text.secondary" sx={{ my: 1 }}>{supply.description}</Typography>
              <Typography variant="body2">SKU: {supply.sku}</Typography>
              <Typography variant="body2">Synthetic availability: {supply.availableUnits} {supply.unitOfMeasure}s</Typography>
            </CardContent>
            <CardActions>
              <Button
                startIcon={<AddCircleOutline />}
                disabled={!supply.isAvailable}
                onClick={() => addSupply(supply)}
              >
                Add to requisition
              </Button>
            </CardActions>
          </Card>
        ))}
      </Box>
      {items.length > 0 && (
        <Button variant="contained" size="large" sx={{ mt: 4 }} onClick={() => navigate('/requisition')}>
          Review requisition ({items.length})
        </Button>
      )}
    </>
  );
};

export default DistributionCenterPage;
