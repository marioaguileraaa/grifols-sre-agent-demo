import React, { useEffect, useState } from 'react';
import {
  Alert,
  Box,
  Button,
  Card,
  CardActions,
  CardContent,
  Chip,
  CircularProgress,
  TextField,
  Typography,
} from '@mui/material';
import { LocalShippingOutlined, Search } from '@mui/icons-material';
import { useNavigate } from 'react-router-dom';
import { DistributionCenter } from '../types';
import { distributionCenterService } from '../services/api';

const HomePage: React.FC = () => {
  const navigate = useNavigate();
  const [centers, setCenters] = useState<DistributionCenter[]>([]);
  const [query, setQuery] = useState('');
  const [error, setError] = useState('');

  useEffect(() => {
    distributionCenterService.getAll().then(setCenters).catch(() =>
      setError('Unable to load the synthetic distribution-center catalog.'));
  }, []);

  const visibleCenters = centers.filter((center) =>
    `${center.name} ${center.region} ${center.description}`.toLowerCase().includes(query.toLowerCase()));

  return (
    <>
      <Box className="hero">
        <Typography variant="overline" sx={{ letterSpacing: 2 }}>Hospital replenishment demo</Typography>
        <Typography variant="h2" component="h1" gutterBottom>Plasma-derived therapy supply coordination</Typography>
        <Typography variant="h6" sx={{ maxWidth: 760, opacity: 0.92 }}>
          Browse fictional distribution centers, prepare a synthetic replenishment requisition,
          and reserve a cold-chain dispatch.
        </Typography>
      </Box>

      <TextField
        fullWidth
        label="Search distribution centers"
        value={query}
        onChange={(event) => setQuery(event.target.value)}
        InputProps={{ startAdornment: <Search color="action" sx={{ mr: 1 }} /> }}
        sx={{ my: 4, maxWidth: 620 }}
      />

      {error && <Alert severity="error">{error}</Alert>}
      {!error && centers.length === 0 && <CircularProgress aria-label="Loading distribution centers" />}

      <Box className="card-grid">
        {visibleCenters.map((center) => (
          <Card key={center.id} variant="outlined">
            <CardContent>
              <Box sx={{ display: 'flex', justifyContent: 'space-between', gap: 2 }}>
                <Typography variant="h5">{center.name}</Typography>
                <Chip label={center.code} color="secondary" size="small" />
              </Box>
              <Typography color="text.secondary" sx={{ my: 2 }}>{center.description}</Typography>
              <Typography variant="body2"><strong>Region:</strong> {center.region}</Typography>
              <Typography variant="body2"><strong>Cold chain:</strong> {center.coldChainRange}</Typography>
              <Typography variant="body2"><strong>Window:</strong> {center.serviceWindow}</Typography>
            </CardContent>
            <CardActions>
              <Button
                startIcon={<LocalShippingOutlined />}
                onClick={() => navigate(`/distribution-centers/${center.id}`)}
              >
                Select supplies
              </Button>
            </CardActions>
          </Card>
        ))}
      </Box>
    </>
  );
};

export default HomePage;
