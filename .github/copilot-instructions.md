# Grifols Plasma Supply fictional SRE demo

- Treat every center, facility, requisition, supply, shipment, correlation ID, and metric as synthetic demo data.
- Keep the visible disclaimer: this is not an official Grifols system, contains no patient/clinical data, makes no real-product/process claims, and provides no medical advice.
- Use the text wordmark only; do not introduce an official logo.
- Preserve the domain names: DistributionCenter, TherapySupply, Requisition, ColdChainDispatch, and Shipment.
- The final dispatch operation is the only intentional incident surface.
- Keep `DEMO_COLD_CHAIN_FAILURE_RATE` typed and startup-validated from 0 through 100.
- At 100, preserve HTTP 503, code `COLD_CHAIN_GATEWAY_UNAVAILABLE`, safe message, and correlation ID.
- Keep structured logs with correlation/requisition/shipment IDs, synthetic center, error code, and fictional root-cause clue; never log secrets.
- Azure SRE Agent stays `accessLevel=Low` and `mode=Review`.
- Do not broaden RBAC beyond the documented roles.
- ACR pulls use the application UAMI only; never use registry passwords.
- Do not deploy from tests or CI. Azure changes require account/subscription/resource-group safeguards.
- GitHub PAT/OAuth credentials may exist only in process environment or interactive OAuth; never persist them.
