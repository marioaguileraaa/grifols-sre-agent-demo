import AcUnitIcon from '@mui/icons-material/AcUnit';
import AssignmentOutlinedIcon from '@mui/icons-material/AssignmentOutlined';
import { AppBar, Badge, Box, Button, Container, Toolbar, Typography } from '@mui/material';
import { Link as RouterLink } from 'react-router-dom';

interface AppHeaderProps {
  selectedCount: number;
}

export default function AppHeader({ selectedCount }: AppHeaderProps) {
  return (
    <AppBar position="sticky" color="inherit" elevation={0} sx={{ borderBottom: '1px solid', borderColor: 'divider' }}>
      <Container maxWidth="lg">
        <Toolbar disableGutters sx={{ minHeight: 72, gap: 2 }}>
          <Box sx={{ bgcolor: 'primary.main', color: 'white', borderRadius: 2, p: 1, display: 'flex' }}>
            <AcUnitIcon aria-hidden="true" />
          </Box>
          <Box component={RouterLink} to="/" sx={{ color: 'inherit', textDecoration: 'none', flex: 1 }}>
            <Typography variant="h6" fontWeight={800} color="primary.dark">
              Grifols Plasma Supply
            </Typography>
            <Typography variant="caption" color="text.secondary">
              Synthetic cold-chain operations
            </Typography>
          </Box>
          <Badge badgeContent={selectedCount} color="secondary">
            <Button
              component={RouterLink}
              to="/requisition"
              startIcon={<AssignmentOutlinedIcon />}
              variant={selectedCount ? 'contained' : 'outlined'}
              aria-label={`Review requisition, ${selectedCount} supplies selected`}
            >
              <Box component="span" sx={{ display: { xs: 'none', sm: 'inline' } }}>Requisition</Box>
            </Button>
          </Badge>
        </Toolbar>
      </Container>
    </AppBar>
  );
}
