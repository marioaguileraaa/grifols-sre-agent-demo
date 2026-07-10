# Grifols Plasma Supply — demostración de SRE Agent

Aplicación técnica ficticia y no oficial para demostrar investigación y recuperación de un incidente de reserva logística de cadena de frío en Azure Container Apps.

> **Aviso obligatorio:** todo el contenido y todos los identificadores son sintéticos. La aplicación no contiene datos de pacientes ni datos clínicos, no representa procesos reales de Grifols y no realiza afirmaciones sobre productos, eficacia o resultados. No utiliza logotipos oficiales.

## Arquitectura

```text
Navegador
  └─ HTTPS → Container App frontend (Nginx, puerto 80)
                ├─ SPA React/TypeScript
                └─ /api y /health → Container App backend (.NET 9, puerto 8080)
                                         ├─ catálogo sintético en memoria
                                         ├─ reserva determinista de cadena de frío
                                         └─ JSON logs + X-Correlation-ID

Azure Monitor
  ├─ Log Analytics (30 días)
  ├─ Application Insights basado en workspace
  ├─ alerta Requests/5xx (total > 5 en 5 min, evaluación cada minuto, severidad 2)
  └─ SRE Agent en modo Review
```

El navegador siempre usa rutas del mismo origen. `BACKEND_URL` se inyecta al iniciar Nginx y nunca se compila una URL de despliegue en el bundle.

## Flujo funcional

1. Explorar y filtrar centros de distribución sintéticos.
2. Seleccionar suministros terapéuticos genéricos.
3. crear una requisición de reposición para una instalación receptora sintética.
4. reservar el despacho de cadena de frío.
5. consultar el envío y sus hitos de seguimiento.

API:

- `/api/distribution-centers`
- `/api/therapy-supplies`
- `/api/requisitions`
- `/api/dispatch-reservations`
- `/api/shipments`
- `/health`

## Incidente controlado

`DEMO_COLD_CHAIN_FAILURE_RATE` acepta exclusivamente un entero de `0` a `100` y usa `0` si no se configura. La aplicación no arranca con otro valor.

- `0`: todas las reservas válidas tienen éxito.
- `100`: todas devuelven HTTP `503` y `COLD_CHAIN_GATEWAY_UNAVAILABLE`.
- `1–99`: un hash estable del ID de requisición elige un bucket reproducible.

Cada respuesta incluye `X-Correlation-ID`; el error incluye el mismo valor en el cuerpo. El backend registra campos JSON para correlación, requisición, centro, tasa, bucket, código y una pista segura de configuración. Nunca crea un envío cuando falla la reserva.

## Salvaguarda de destino

Todos los scripts usan por defecto:

| Valor | Destino permitido |
|---|---|
| Suscripción | `5305e853-a63b-4b82-9a3f-6fde18c1a798` |
| Grupo de recursos existente | `rg-demo-sre-agent-v1` |
| Región | `eastus2` |

`scripts/Guard-AzureTarget.ps1` detiene la ejecución si la cuenta activa, el grupo o la región no coinciden. La plantilla Bicep referencia el grupo como **existente**: no lo crea ni lo elimina.

## Requisitos

- PowerShell 7
- Azure CLI con extensiones `containerapp` y `account`
- Azure Developer CLI opcional
- .NET SDK 9
- Node.js 24 y npm 11
- GitHub CLI para crear el issue sintético opcional
- Permisos para despliegues a nivel de suscripción y grupo

Docker local no es necesario: `Deploy-Applications.ps1` usa compilaciones remotas de ACR.

```powershell
az login
az account set --subscription 5305e853-a63b-4b82-9a3f-6fde18c1a798
.\scripts\Guard-AzureTarget.ps1
```

## Desarrollo local

Backend:

```powershell
dotnet restore .\GrifolsPlasmaSupply.sln --source https://api.nuget.org/v3/index.json
$env:DEMO_COLD_CHAIN_FAILURE_RATE = '0'
dotnet run --project .\GrifolsPlasmaSupply.Api
```

Frontend (el proxy de desarrollo dirige `/api` a `http://localhost:5291`):

```powershell
Set-Location .\grifols-plasma-supply-frontend
npm ci
npm start
```

## Infraestructura

`infra/main.bicep` despliega en el grupo existente:

- Log Analytics con retención de 30 días y Application Insights basado en workspace.
- ACR Basic con administrador y pull anónimo deshabilitados.
- Container Apps Environment integrado con Log Analytics.
- identidad UAMI compartida con `AcrPull`; no existen contraseñas de registro.
- backend externo en `8080` y frontend externo en `80`.
- UAMI de SRE y `Microsoft.App/agents@2026-01-01` llamado `sre-agent-grifols-v1`.
- action group y alerta métrica de severidad 2.

Los Container Apps empiezan con la imagen pública de ejemplo para permitir aprovisionar antes de publicar imágenes propias.

### Riesgo RBAC que debe revisarse

La UAMI del agente recibe Reader, Log Analytics Reader, Monitoring Reader y Container Apps Contributor en el grupo, además de **Monitoring Contributor en toda la suscripción**. Estos dos permisos de escritura son amplios. El agente está en modo **Review**, de modo que toda mitigación exige aprobación humana. Revise asignaciones y ámbito antes de desplegar.

Validación local sin tocar Azure:

```powershell
az bicep build --file .\infra\main.bicep
```

El operador autorizado debe ejecutar después su revisión de políticas, cuotas y `what-if` antes del despliegue:

```powershell
az deployment sub what-if `
  --subscription 5305e853-a63b-4b82-9a3f-6fde18c1a798 `
  --location eastus2 `
  --template-file .\infra\main.bicep `
  --parameters .\infra\main.parameters.json

az deployment sub create `
  --name grifols-plasma-supply-v1 `
  --subscription 5305e853-a63b-4b82-9a3f-6fde18c1a798 `
  --location eastus2 `
  --template-file .\infra\main.bicep `
  --parameters .\infra\main.parameters.json
```

## Imágenes, actualización y smoke test

```powershell
.\scripts\Deploy-Applications.ps1
.\scripts\Test-Smoke.ps1
```

El script crea tags inmutables, ejecuta dos `az acr build`, configura el pull con la UAMI, actualiza las revisiones, espera readiness y verifica frontend, backend y proxy del mismo origen.

## Configurar SRE Agent

```powershell
.\scripts\Configure-SreAgent.ps1
```

El script obtiene en memoria un token para `https://azuresre.dev`, realiza `PUT` idempotentes y verifica:

- conector Log Analytics con identidad administrada;
- autenticación GitHub actual mediante `/api/v2/github/oauth/config` o, si se proporciona solo al proceso, `GITHUB_PAT` mediante `/api/v2/github/domains/github_com`;
- repositorio público `/api/v2/repos/grifols-sre-agent-demo`;
- subagente `code-analyzer` y respuesta Sev2 `cold-chain-sev2-review` con payloads directos de data plane y modo Review;
- límite mensual de 1000 unidades de agente.

No persiste ni imprime tokens o PAT. Si no se proporciona `GITHUB_PAT`, el script muestra la URL de autorización devuelta por el agente; complete el consentimiento interactivo y vuelva a ejecutarlo.

Para la automatización de GitHub, configure exclusivamente el secreto `SRE_TRIGGER_URL`. El workflow se activa al añadir la etiqueta `sre-investigate` a una incidencia cuyo título empiece por `[SYNTHETIC]`, o manualmente con un ID `SYNTH-*` y la confirmación sintética activada.

## Cronología de la demostración

1. Comprobar que la tasa es `0` y ejecutar `Test-Smoke.ps1`.
2. Ejecutar `Start-ColdChainIncident.ps1`; genera al menos diez 503 válidos en menos de cinco minutos e imprime cada correlación.
3. Esperar la evaluación de la alerta (un minuto).
4. Pedir al agente: “Investiga el incidente sintético `COLD_CHAIN_GATEWAY_UNAVAILABLE`; correlaciona métrica, logs y revisión, y propone una mitigación sin ejecutarla”.
5. Revisar la propuesta y aprobar explícitamente solo la mitigación prevista.
6. Ejecutar `Recover-ColdChainIncident.ps1`.
7. Confirmar respuesta 2xx, ID de envío, tracking y recuperación de la métrica.

Runbook: [`docs/runbooks/cold-chain-reservation-5xx.md`](docs/runbooks/cold-chain-reservation-5xx.md).

## Validación

```powershell
dotnet restore .\GrifolsPlasmaSupply.sln --source https://api.nuget.org/v3/index.json
dotnet test .\GrifolsPlasmaSupply.sln --no-restore

Set-Location .\grifols-plasma-supply-frontend
npm ci
$env:CI = 'true'
npm test -- --watchAll=false --runInBand
npm run typecheck
npm run build
Set-Location ..

az bicep build --file .\infra\main.bicep
```

Las pruebas cubren éxito, fallo determinista, configuración inválida, validación, ausencia de envíos tras fallo, propagación de errores, aviso visible y flujo crítico.

## Coste y limpieza

ACR, Log Analytics, Application Insights, Container Apps y SRE Agent pueden generar coste. Use límites del entorno demo y revise la ingestión. Para limpiar, elimine únicamente los recursos con tags `purpose=sre-agent-demo`, `environment=demo` y `dataClassification=synthetic`; **no elimine automáticamente el grupo compartido**. Revise también las asignaciones RBAC de suscripción.

## Solución de problemas

- `401/403`: confirme cuenta, suscripción, consentimiento y RBAC; no sustituya identidad administrada por secretos.
- Container App sin revisión ready: inspeccione `az containerapp revision list` y los logs de consola.
- Nginx devuelve `502`: confirme `BACKEND_URL` y `/health` del backend.
- No se activa la alerta: confirme que el total es mayor que `5` dentro de cinco minutos (el script envía `10` respuestas 503) y la dimensión `statusCodeCategory=5xx`.
- Configuración rechazada al arrancar: corrija `DEMO_COLD_CHAIN_FAILURE_RATE` a un entero entre 0 y 100.
- Restore NuGet sin origen: use explícitamente `https://api.nuget.org/v3/index.json`.

## Atribución de migración

Esta demostración se migró arquitectónicamente desde el seed abierto **Grubify food-delivery**; toda su terminología funcional anterior fue retirada y no representa el dominio operativo actual.
