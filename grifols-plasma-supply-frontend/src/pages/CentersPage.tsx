import { useEffect, useMemo, useState } from 'react';
import AcUnitIcon from '@mui/icons-material/AcUnit';
import HubOutlinedIcon from '@mui/icons-material/HubOutlined';
import SearchIcon from '@mui/icons-material/Search';
import { Alert, Box, Button, Card, CardActions, CardContent, Chip, CircularProgress, InputAdornment, Stack, TextField, Typography } from '@mui/material';
import { Link as RouterLink } from 'react-router-dom';
import { supplyApi } from '../services/api';
import { DistributionCenter } from '../types';

export default function CentersPage() {
  const [centers, setCenters] = useState<DistributionCenter[]>([]);
  const [query, setQuery] = useState('');
  const [region, setRegion] = useState('all');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    supplyApi.getDistributionCenters()
      .then(setCenters)
      .catch(() => setError('Distribution centers could not be loaded.'))
      .finally(() => setLoading(false));
  }, []);

  const regions = Array.from(new Set(centers.map(center => center.region)));
  const filtered = useMemo(() => centers.filter(center =>
    (region === 'all' || center.region === region)
    && `${center.name} ${center.city} ${center.country}`.toLowerCase().includes(query.toLowerCase())),
  [centers, query, region]);

  return (
    <Stack spacing={4}>
      <Box className="hero">
        <Chip icon={<AcUnitIcon />} label="2–8 °C synthetic network" sx={{ mb: 3, bgcolor: 'rgba(255,255,255,.9)' }} />
        <Typography variant="h1" maxWidth={760}>Resilient plasma supply coordination</Typography>
        <Typography variant="h6" sx={{ mt: 2, maxWidth: 680, opacity: 0.9, fontWeight: 400 }}>
          Explore a fictional distribution network, prepare a replenishment requisition, and reserve a
          temperature-monitored dispatch.
        </Typography>
      </Box>

      <Box>
        <Typography variant="h2" gutterBottom>Distribution centers</Typography>
        <Typography color="text.secondary">Search the synthetic operations network and choose an origin.</Typography>
      </Box>

      <Stack direction={{ xs: 'column', md: 'row' }} spacing={2}>
        <TextField
          fullWidth
          label="Search distribution centers"
          value={query}
          onChange={event => setQuery(event.target.value)}
          InputProps={{ startAdornment: <InputAdornment position="start"><SearchIcon /></InputAdornment> }}
        />
        <TextField
          select
          SelectProps={{ native: true }}
          label="Region"
          value={region}
          onChange={event => setRegion(event.target.value)}
          sx={{ minWidth: 230 }}
        >
          <option value="all">All regions</option>
          {regions.map(item => <option key={item} value={item}>{item}</option>)}
        </TextField>
      </Stack>

      {loading && <Box textAlign="center"><CircularProgress aria-label="Loading centers" /></Box>}
      {error && <Alert severity="error">{error}</Alert>}
      <Box sx={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(270px, 1fr))', gap: 3 }}>
        {filtered.map(center => (
          <Card key={center.id} className="supply-card" variant="outlined">
            <CardContent>
              <HubOutlinedIcon color="primary" fontSize="large" />
              <Typography variant="h5" sx={{ mt: 2 }} fontWeight={700}>{center.name}</Typography>
              <Typography color="text.secondary" sx={{ mt: 1 }}>{center.city}, {center.country}</Typography>
              <Stack direction="row" spacing={1} sx={{ mt: 2, flexWrap: 'wrap' }}>
                <Chip size="small" label={center.region} />
                <Chip size="small" color="secondary" variant="outlined" label={center.temperatureCapability} />
              </Stack>
            </CardContent>
            <CardActions>
              <Button
                component={RouterLink}
                to={`/centers/${center.id}`}
                aria-label={`Browse supplies from ${center.name}`}
              >
                Browse supplies
              </Button>
            </CardActions>
          </Card>
        ))}
      </Box>
    </Stack>
  );
}
