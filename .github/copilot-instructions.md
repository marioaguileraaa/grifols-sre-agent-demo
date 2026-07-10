<!-- Use this file to provide workspace-specific custom instructions to Copilot. For more details, visit https://code.visualstudio.com/docs/copilot/copilot-customization#_use-a-githubcopilotinstructionsmd-file -->

# Grifols Plasma Supply SRE Demo

This repository is a fictional, unofficial technical demonstration for synthetic plasma-supply logistics on Azure Container Apps. Never add patient data, clinical data, official logos, real product claims, credentials, or private operational details.

## Tech Stack
- **Frontend**: React with strict TypeScript, Material UI, React Router, same-origin typed `fetch`
- **Backend**: .NET 9 Web API with Controllers
- **Runtime**: Nginx reverse proxy plus Azure Container Apps
- **Infrastructure**: subscription-scope Bicep targeting the guarded existing demo resource group

## Architecture
- Synthetic distribution centers and generic therapy supplies
- Replenishment requisitions, cold-chain dispatch reservations, and shipment tracking
- Deterministic incident injection through `DEMO_COLD_CHAIN_FAILURE_RATE`
- Correlation IDs in response headers, structured errors, UI, and JSON logs

## Development Guidelines
- Use TypeScript strict mode
- Follow Material-UI design patterns
- Preserve structured API errors and correlation IDs
- Use async/await for API calls
- Keep browser API traffic on same-origin `/api`
- Keep all incident automation explicitly synthetic and target-guarded
- Use managed identities for image pulls; never add registry credentials or PAT persistence

## API Endpoints
- `/api/distribution-centers`
- `/api/therapy-supplies`
- `/api/requisitions`
- `/api/dispatch-reservations`
- `/api/shipments`
- `/health`

## UI Components
- Responsive blue, teal, and white operations UI
- Persistent fictional/synthetic-data disclaimer
- Accessible center-to-requisition-to-shipment flow
- No external product imagery or official branding assets

The injected 503 is `COLD_CHAIN_GATEWAY_UNAVAILABLE`. A failed reservation must never create a shipment. Write operations by the SRE Agent remain approval-gated in Review mode.
