import React from 'react';
import { Box, Button, Card, CardContent, IconButton, TextField, Typography } from '@mui/material';
import { DeleteOutline } from '@mui/icons-material';
import { useNavigate } from 'react-router-dom';
import { useRequisition } from '../state/RequisitionContext';

const RequisitionPage: React.FC = () => {
  const navigate = useNavigate();
  const { items, updateQuantity, removeSupply } = useRequisition();

  if (items.length === 0) {
    return (
      <Box sx={{ textAlign: 'center', py: 10 }}>
        <Typography variant="h3">Replenishment requisition</Typography>
        <Typography color="text.secondary" sx={{ my: 2 }}>No synthetic supplies selected.</Typography>
        <Button variant="contained" onClick={() => navigate('/')}>Browse distribution centers</Button>
      </Box>
    );
  }

  return (
    <>
      <Typography variant="h3" component="h1" gutterBottom>Replenishment requisition</Typography>
      <Typography color="text.secondary" sx={{ mb: 3 }}>
        Review synthetic shipping units before requesting a cold-chain dispatch reservation.
      </Typography>
      {items.map(({ supply, quantity }) => (
        <Card key={supply.id} variant="outlined" sx={{ mb: 2 }}>
          <CardContent sx={{ display: 'flex', alignItems: 'center', gap: 3, flexWrap: 'wrap' }}>
            <Box sx={{ flex: 1, minWidth: 260 }}>
              <Typography variant="h6">{supply.name}</Typography>
              <Typography color="text.secondary">{supply.sku} · {supply.category}</Typography>
            </Box>
            <TextField
              label="Shipping units"
              type="number"
              value={quantity}
              inputProps={{ min: 1, max: 500 }}
              onChange={(event) => updateQuantity(supply.id, Number(event.target.value))}
              sx={{ width: 150 }}
            />
            <IconButton aria-label={`Remove ${supply.name}`} onClick={() => removeSupply(supply.id)}>
              <DeleteOutline />
            </IconButton>
          </CardContent>
        </Card>
      ))}
      <Button variant="contained" size="large" onClick={() => navigate('/cold-chain-dispatch')}>
        Confirm cold-chain dispatch
      </Button>
    </>
  );
};

export default RequisitionPage;
