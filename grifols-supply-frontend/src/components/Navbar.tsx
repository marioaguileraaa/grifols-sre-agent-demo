import React from 'react';
import { Alert, AppBar, Badge, Box, Button, Toolbar, Typography } from '@mui/material';
import { AcUnit, Inventory2Outlined } from '@mui/icons-material';
import { useNavigate } from 'react-router-dom';
import { useRequisition } from '../state/RequisitionContext';

const Navbar: React.FC = () => {
  const navigate = useNavigate();
  const { items } = useRequisition();

  return (
    <>
      <AppBar position="sticky" elevation={1}>
        <Toolbar sx={{ gap: 2 }}>
          <AcUnit aria-hidden />
          <Typography
            component="button"
            variant="h6"
            onClick={() => navigate('/')}
            sx={{
              appearance: 'none',
              border: 0,
              background: 'transparent',
              color: 'inherit',
              cursor: 'pointer',
              fontWeight: 750,
            }}
          >
            Grifols Plasma Supply
          </Typography>
          <Box sx={{ flexGrow: 1 }} />
          <Button color="inherit" onClick={() => navigate('/requisition')} startIcon={
            <Badge badgeContent={items.length} color="secondary"><Inventory2Outlined /></Badge>
          }>
            Requisition
          </Button>
        </Toolbar>
      </AppBar>
      <Alert severity="info" icon={false} sx={{ borderRadius: 0, justifyContent: 'center' }}>
        Fictional technical demo only. Not an official Grifols system. Synthetic data only; no patient or clinical data,
        real-product claims, process claims, or medical advice.
      </Alert>
    </>
  );
};

export default Navbar;
