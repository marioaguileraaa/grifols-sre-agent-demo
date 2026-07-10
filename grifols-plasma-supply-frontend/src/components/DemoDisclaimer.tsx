import InfoOutlinedIcon from '@mui/icons-material/InfoOutlined';
import { Alert, Container } from '@mui/material';

export default function DemoDisclaimer() {
  return (
    <Container maxWidth="lg" component="footer" sx={{ pb: 3 }}>
      <Alert severity="info" icon={<InfoOutlinedIcon />} role="note">
        Fictional and unofficial demonstration using synthetic data only. It contains no patient or clinical data
        and makes no claims about real Grifols products, efficacy, or processes.
      </Alert>
    </Container>
  );
}
