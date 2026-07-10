# Runbook: 5xx en reserva de cadena de frío

## Alcance y seguridad

Este runbook se aplica únicamente al incidente ficticio y sintético de Grifols Plasma Supply. No introduzca datos de pacientes, datos clínicos, credenciales ni información operativa real. El agente está en modo Review: toda escritura requiere aprobación.

Destino:

- suscripción `5305e853-a63b-4b82-9a3f-6fde18c1a798`
- grupo `rg-demo-sre-agent-v1`
- región `eastus2`
- backend `ca-grifols-backend-v1`
- workspace `law-grifols-sre-v1`
- alerta `alert-grifols-cold-chain-5xx-v1`

## Señal de alerta

La alerta tiene severidad 2 y evalúa cada minuto el total de `Requests` del backend durante cinco minutos:

- namespace: `Microsoft.App/containerApps`
- métrica: `Requests`
- dimensión: `statusCodeCategory`
- filtro: `5xx`
- operador: `GreaterThanOrEqual`
- umbral: `8`

Inspección:

```powershell
az monitor metrics alert show `
  --subscription 5305e853-a63b-4b82-9a3f-6fde18c1a798 `
  --resource-group rg-demo-sre-agent-v1 `
  --name alert-grifols-cold-chain-5xx-v1

$backendId = az containerapp show `
  --subscription 5305e853-a63b-4b82-9a3f-6fde18c1a798 `
  --resource-group rg-demo-sre-agent-v1 `
  --name ca-grifols-backend-v1 `
  --query id -o tsv

az monitor metrics list `
  --resource $backendId `
  --metric Requests `
  --filter "statusCodeCategory eq '5xx'" `
  --interval PT1M `
  --aggregation Total
```

## Correlación en Log Analytics

Errores recientes:

```kusto
ContainerAppConsoleLogs_CL
| where TimeGenerated > ago(30m)
| where ContainerAppName_s == "ca-grifols-backend-v1"
| where Log_s has "COLD_CHAIN_GATEWAY_UNAVAILABLE"
| project TimeGenerated, RevisionName_s, Log_s
| order by TimeGenerated desc
```

Extraer campos del JSON emitido por `ILogger`:

```kusto
ContainerAppConsoleLogs_CL
| where TimeGenerated > ago(30m)
| where ContainerAppName_s == "ca-grifols-backend-v1"
| extend Log = parse_json(Log_s)
| extend Message = tostring(Log.Message)
| where Message has "Cold-chain dispatch reservation failed"
| parse Message with * "CorrelationId=" CorrelationId " RequisitionId=" RequisitionId " DistributionCenter=" DistributionCenter " ErrorCode=" ErrorCode " FailureRate=" FailureRate:int " FailureBucket=" FailureBucket:int " SourceClue=" SourceClue
| project TimeGenerated, RevisionName_s, CorrelationId, RequisitionId, DistributionCenter, ErrorCode, FailureRate, FailureBucket, SourceClue
| order by TimeGenerated desc
```

Buscar una correlación concreta:

```kusto
let correlationId = "REEMPLAZAR_CORRELACION";
ContainerAppConsoleLogs_CL
| where TimeGenerated > ago(2h)
| where ContainerAppName_s == "ca-grifols-backend-v1"
| where Log_s has correlationId
| project TimeGenerated, RevisionName_s, ContainerAppName_s, Log_s
| order by TimeGenerated asc
```

Confirmar que no apareció un envío para requisiciones fallidas:

```kusto
let failedRequisition = "REEMPLAZAR_REQUISICION";
ContainerAppConsoleLogs_CL
| where TimeGenerated > ago(2h)
| where ContainerAppName_s == "ca-grifols-backend-v1"
| where Log_s has failedRequisition
| summarize Failures=countif(Log_s has "reservation failed"), Successes=countif(Log_s has "reservation succeeded")
```

## Revisión, configuración y entorno

```powershell
az containerapp revision list `
  --subscription 5305e853-a63b-4b82-9a3f-6fde18c1a798 `
  --resource-group rg-demo-sre-agent-v1 `
  --name ca-grifols-backend-v1 `
  --query "[].{name:name,active:properties.active,health:properties.healthState,created:properties.createdTime}" `
  --output table

az containerapp show `
  --subscription 5305e853-a63b-4b82-9a3f-6fde18c1a798 `
  --resource-group rg-demo-sre-agent-v1 `
  --name ca-grifols-backend-v1 `
  --query "properties.template.containers[0].{image:image,env:env[?name=='DEMO_COLD_CHAIN_FAILURE_RATE']}" `
  --output json
```

No muestre variables que puedan contener secretos. En este demo la variable esperada es `0` en estado normal y `100` durante el incidente.

## Correlación con fuente

- Validación de configuración: `GrifolsPlasmaSupply.Api/Options/ColdChainDemoOptions.cs`
- Decisión determinista, logs y creación de envío: `GrifolsPlasmaSupply.Api/Services/ColdChainReservationService.cs`
- Contrato HTTP 503/correlación: `GrifolsPlasmaSupply.Api/Controllers/DispatchReservationsController.cs`
- Propagación de correlación: `GrifolsPlasmaSupply.Api/Middleware/CorrelationIdMiddleware.cs`
- Infraestructura y alerta: `infra/platform.bicep`
- Inyección y recuperación: `scripts/Start-ColdChainIncident.ps1` y `scripts/Recover-ColdChainIncident.ps1`

La pista segura esperada es `Configuration:DEMO_COLD_CHAIN_FAILURE_RATE -> ColdChainReservationGateway`; no contiene endpoints internos.

## Mitigación

1. Confirme que el caso es sintético.
2. Confirme que los 503 comparten el código esperado y que la tasa activa es `100`.
3. Revise la revisión y descarte una regresión distinta.
4. Proponga cambiar solo `DEMO_COLD_CHAIN_FAILURE_RATE` a `0`.
5. Obtenga aprobación humana.
6. Ejecute:

```powershell
.\scripts\Recover-ColdChainIncident.ps1
```

No desactive la alerta, no reduzca el umbral, no amplíe permisos y no introduzca secretos.

## Verificación y cierre

- El script devuelve HTTP 2xx, ID de envío y tracking.
- La revisión nueva figura ready.
- `/health` responde correctamente.
- Dos reservas válidas consecutivas crean envíos.
- `Requests` 5xx vuelve a cero en ventanas posteriores.
- No aparecen nuevos `COLD_CHAIN_GATEWAY_UNAVAILABLE`.
- Se registran correlaciones de fallo y recuperación en el informe.

```powershell
.\scripts\Test-Smoke.ps1
.\scripts\Recover-ColdChainIncident.ps1
.\scripts\Recover-ColdChainIncident.ps1
```

## Plantilla de informe

```text
ID: SYNTH-AAAA-MM-DD-NNN
Clasificación: sintético / demo
Inicio UTC:
Detección UTC:
Recuperación UTC:
Alerta y severidad:
Revisión afectada:
Imagen afectada:
Correlaciones representativas:
Requisiciones sintéticas afectadas:
Código: COLD_CHAIN_GATEWAY_UNAVAILABLE
Tasa y buckets observados:
Causa técnica:
Pista de fuente:
Mitigación propuesta:
Aprobador:
Mitigación ejecutada:
Envíos de verificación:
Tracking de verificación:
Estado de métrica/logs:
Acciones de seguimiento:
Confirmación de ausencia de datos sensibles:
```
