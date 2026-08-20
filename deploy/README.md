# Deploy

Two ready-to-run paths. Both assume **Service B (ai-planner) reachability**: it runs
on your local machine with Ollama (see [instruction.txt](../instruction.txt) Part C /
[DEVOPS_ARCHITECTURE.md](../DEVOPS_ARCHITECTURE.md) §2b).

---

## 1. Docker Compose (local, all-in-one)

Runs everything on one host: PostgreSQL + Trip Service + AI Planner + frontend.

```bash
# from the repo root
cp env.example .env          # set INTERNAL_API_TOKEN, AI provider, etc.
docker compose up --build
```
- Frontend → http://localhost:8080 · Trip API → :5001 · AI Planner → :5002 · DB → :5432
- Migrations run automatically on Trip Service start.
- For AI planning, have Ollama running on the host (`ollama pull llama3.1`) or set
  `AI_PROVIDER=openai` + `OPENAI_API_KEY` in `.env`.

---

## 2. Kubernetes (Helm chart)

Chart: [`helm/travel-planner`](helm/travel-planner). Deploys **Service A** (frontend +
trip-service) plus an **optional in-cluster PostgreSQL**. Service B stays on your local
machine; point `aiPlanner.url` at its tunnel.

### Quick self-contained run (any cluster: kind / minikube / EKS)
```bash
# build + load images (kind example); on a cloud cluster push to your registry instead
docker build -t trip-service:1.0.0 services/trip-service
docker build --build-arg VITE_TRIP_SERVICE_URL="" -t frontend:1.0.0 frontend
kind load docker-image trip-service:1.0.0 frontend:1.0.0

helm install tp deploy/helm/travel-planner \
  --namespace travel-staging --create-namespace \
  --set image.registry="" \
  --set aiPlanner.url="https://<your-tunnel>.trycloudflare.com" \
  --set secrets.internalApiToken="<same-token-as-service-B>" \
  --set ingress.enabled=false          # use port-forward instead of ingress

kubectl -n travel-staging port-forward svc/frontend 8080:80
# open http://localhost:8080
```

### Staging on EKS (in-cluster Postgres)
```bash
helm upgrade --install tp deploy/helm/travel-planner \
  -n travel-staging --create-namespace \
  -f deploy/helm/travel-planner/values-staging.yaml \
  --set image.registry=<your-ECR>/travel-planner
```

### Production on EKS (managed RDS, HPA, ServiceMonitor, NetworkPolicy)
```bash
helm upgrade --install tp deploy/helm/travel-planner \
  -n travel-prod --create-namespace \
  -f deploy/helm/travel-planner/values-prod.yaml \
  --set image.registry=<your-ECR>/travel-planner \
  --set externalDatabase.url="postgresql+psycopg2://travel:<pass>@<rds-host>:5432/travel"
```
For real prod, prefer `--set secrets.create=false --set secrets.existingSecret=<name>`
and supply secrets from your secrets manager (External Secrets / Sealed Secrets).

### Key values
| Value | Purpose |
|---|---|
| `image.registry` / `image.tag` | where to pull images from |
| `aiPlanner.url` | tunnel endpoint of your local Service B |
| `secrets.internalApiToken` | must match Service B's `INTERNAL_API_TOKEN` |
| `postgres.enabled` | `true` = in-cluster DB; `false` = use `externalDatabase.url` (RDS) |
| `externalDatabase.url` | SQLAlchemy URL when `postgres.enabled=false` |
| `ingress.enabled` / `ingress.host` | public HTTPS via ingress-nginx + cert-manager |
| `tripService.autoscaling.enabled` | HPA for trip-service |
| `serviceMonitor.enabled` | Prometheus Operator scraping |
| `networkPolicy.enabled` | restrict who can reach trip-service |

Full step-by-step (EKS + ECR + RDS + tunnel + monitoring): [instruction.txt](../instruction.txt).

### Uninstall
```bash
helm uninstall tp -n travel-staging
```

---

## Validated
- `docker compose config` — valid (db, trip-service, ai-planner-service, frontend).
- `helm lint` — passes for default / staging / prod values.
- `helm template` — renders correctly (staging: in-cluster Postgres; prod: RDS + HPA +
  ServiceMonitor + NetworkPolicy).
- `kubeconform` — rendered manifests are schema-valid Kubernetes.
