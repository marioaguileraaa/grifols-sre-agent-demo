# Runbook: 5xx en reserva de despacho de cadena de frío

> Demo ficticio con datos sintéticos. No es un sistema oficial de Grifols, no contiene datos clínicos o de pacientes y no representa productos ni procesos reales.

## Alcance y señales

- Recurso: `ca-grifols-supply-api`.
- Operación: `POST /api/cold-chain-dispatch`.
- Error esperado: HTTP `503`, `COLD_CHAIN_GATEWAY_UNAVAILABLE`.
- Alerta: `alert-grifols-backend-5xx`, severidad 2, más de cinco `Requests` con `statusCodeCategory=5xx` en cinco minutos, evaluación cada minuto.
- Cambio reversible: `DEMO_COLD_CHAIN_FAILURE_RATE` de `100` a `0`.

## 1. Confirmar Azure Monitor

En **Metrics** del Container App:

1. métrica `Requests`;
2. agregación `Sum`;
3. split/filter `statusCodeCategory = 5xx`;
4. granularidad un minuto;
5. rango de tiempo de los últimos 30 minutos.

Comprobar el estado de la alerta:

```powershell
az monitor metrics alert show `
  --subscription 5305e853-a63b-4b82-9a3f-6fde18c1a798 `
  --resource-group rg-demo-sre-agent-v1 `
  --name alert-grifols-backend-5xx
```

## 2. Correlacionar en Log Analytics

Fallos estructurados:

```kusto
ContainerAppConsoleLogs_CL
| where TimeGenerated > ago(30m)
| where ContainerAppName_s == "ca-grifols-supply-api"
| where Log_s has "COLD_CHAIN_GATEWAY_UNAVAILABLE"
| extend LogJson = parse_json(Log_s)
| project TimeGenerated, RevisionName_s, Log_s, LogJson
| order by TimeGenerated desc
```

Correlation IDs y pista de causa:

```kusto
ContainerAppConsoleLogs_CL
| where TimeGenerated > ago(30m)
| where ContainerAppName_s == "ca-grifols-supply-api"
| where Log_s has "Cold-chain dispatch reservation failed"
| where Log_s has "SyntheticGatewayRoute=demo-cold-chain-reservation.invalid"
| project TimeGenerated, RevisionName_s, Log_s
| order by TimeGenerated desc
```

Volumen por revisión:

```kusto
ContainerAppConsoleLogs_CL
| where TimeGenerated > ago(1h)
| where ContainerAppName_s == "ca-grifols-supply-api"
| summarize Failures=countif(Log_s has "COLD_CHAIN_GATEWAY_UNAVAILABLE") by RevisionName_s, bin(TimeGenerated, 1m)
| order by TimeGenerated desc
```

Eventos de revisión/replica:

```kusto
ContainerAppSystemLogs_CL
| where TimeGenerated > ago(1h)
| where ContainerAppName_s == "ca-grifols-supply-api"
| project TimeGenerated, RevisionName_s, Reason_s, Log_s
| order by TimeGenerated desc
```

## 3. Revisar configuración y revisión

```powershell
az containerapp show `
  --subscription 5305e853-a63b-4b82-9a3f-6fde18c1a798 `
  --resource-group rg-demo-sre-agent-v1 `
  --name ca-grifols-supply-api `
  --query "properties.template.containers[0].{image:image,env:env}" -o json

az containerapp revision list `
  --subscription 5305e853-a63b-4b82-9a3f-6fde18c1a798 `
  --resource-group rg-demo-sre-agent-v1 `
  --name ca-grifols-supply-api -o table
```

Confirmar:

- última revisión `Healthy/Running`;
- imagen esperada;
- `DEMO_COLD_CHAIN_FAILURE_RATE=100`;
- no hay secrets en logs ni configuración presentada al incidente.

## 4. Correlacionar con repositorio

En la rama pública `main`, revisar:

- `GrifolsSupply.Api/Options/ColdChainDemoOptions.cs`: validación 0–100;
- `GrifolsSupply.Api/Services/ColdChainDispatchService.cs`: fallo determinista, código estable, pista y logs;
- `GrifolsSupply.Api/Controllers/ColdChainDispatchController.cs`: contrato HTTP 503/correlation ID;
- `scripts/start-incident.ps1` y `scripts/recover-incident.ps1`: trigger y rollback;
- `infra/main.bicep`: variable inicial a `0` y alerta.

Azure SRE Agent debe citar archivo y línea, contrastar la revisión activa y operar en modo Review.

## 5. Proponer mitigación

Mitigación mínima:

```powershell
az containerapp update `
  --subscription 5305e853-a63b-4b82-9a3f-6fde18c1a798 `
  --resource-group rg-demo-sre-agent-v1 `
  --name ca-grifols-supply-api `
  --set-env-vars DEMO_COLD_CHAIN_FAILURE_RATE=0
```

No aprobar:

- rollback de imagen si la imagen no cambió;
- cambios de red, RBAC o secretos;
- `Contributor` general;
- eliminación de recursos;
- cambios que oculten errores o silencien logs.

## 6. Aprobar en Review

Verificar antes de aprobar:

- acción limitada a `ca-grifols-supply-api`;
- única modificación `DEMO_COLD_CHAIN_FAILURE_RATE=0`;
- identidad `id-grifols-sre-v1`;
- ausencia de secretos;
- plan de verificación incluido.

## 7. Verificar recuperación

```powershell
.\scripts\recover-incident.ps1
```

La salida debe mostrar HTTP `201` implícito, tracking ID y correlation ID. Después:

```kusto
ContainerAppConsoleLogs_CL
| where TimeGenerated > ago(15m)
| where ContainerAppName_s == "ca-grifols-supply-api"
| summarize Failures=countif(Log_s has "COLD_CHAIN_GATEWAY_UNAVAILABLE"),
            Successes=countif(Log_s has "Cold-chain dispatch reserved")
          by bin(TimeGenerated, 1m)
| order by TimeGenerated desc
```

Confirmar una reserva correcta después de la nueva revisión y ausencia de nuevos 503. La alerta puede tardar una ventana en resolver.

## Plantilla de informe de incidente

```text
Título:
Severidad: Sev2 (demo)
Estado:
Inicio UTC:
Detección:
Recurso/revisión:
Impacto sintético:

Evidencia
- Alert ID:
- Ventana y recuento 5xx:
- Correlation IDs:
- Requisition IDs:
- Distribution center:
- Error code:
- RootCauseClue:
- Archivos/líneas:

Causa raíz ficticia
- Configuración:
- Revisión que introdujo el cambio:
- Por qué es determinista:

Mitigación propuesta
- Acción:
- Identidad/RBAC:
- Riesgo:
- Aprobador Review:
- Hora de aprobación:

Verificación
- Revisión Healthy/Running:
- HTTP:
- Tracking ID:
- KQL posterior:
- Estado final de alerta:

Seguimiento
- Mejoras:
- Propietario:
- Fecha objetivo:
- Confirmación de que no se usaron datos reales:
```
