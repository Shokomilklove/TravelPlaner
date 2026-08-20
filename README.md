# Travel Planner

A production-grade, multi-service application that helps users plan the best
vacation trip — flights, accommodation and activities — with AI-generated
itineraries and budget suggestions.

- **Frontend** — React (Vite) single-page app.
- **Trip Service (Backend A)** — Flask REST API. Owns PostgreSQL, JWT auth,
  users, trips, itineraries. The only service the browser talks to.
- **AI Planner Service (Backend B)** — internal Flask service that builds the
  prompt, calls the LLM (OpenAI **or** Ollama), validates the result and adds
  budget analysis. Stateless.

> **Roles:** this repo is the **application** (developer deliverable). Kubernetes,
> Helm, Terraform, CI/CD, image scanning, and the Prometheus/Grafana/ELK servers
> are owned by DevOps. The apps *expose* Prometheus metrics and structured JSON
> logs; DevOps runs the collectors. See **[forDevOps.txt](forDevOps.txt)** for
> the full operations hand-off.

## Architecture

```
        ┌────────────────────┐
        │   React UI (SPA)    │
        │  (Travel Planner)   │
        └─────────┬──────────┘
                  │  REST + JWT
                  ▼
        ┌────────────────────────────┐        ┌────────────────────┐
        │  Trip Service (Backend A)  │        │   PostgreSQL DB    │
        │  Auth · Users · Trips ·    │◀──────▶│  (Trip Service     │
        │  Itineraries · Save Trips  │        │   only)            │
        └─────────┬──────────────────┘        └────────────────────┘
                  │  internal REST (X-Internal-Token)
                  ▼
        ┌────────────────────────────┐
        │ AI Planner Service (B)     │
        │ Prompt · AI · Optimize ·   │
        │ Budget suggestions         │
        └─────────┬──────────────────┘
                  ▼
          ┌────────────────┐
          │ OpenAI / Ollama│
          └────────────────┘
```

The frontend never talks to the AI Planner directly — only the Trip Service does,
authenticated with a shared internal token.

## Tech stack

| Layer            | Tech                                                            |
|------------------|-----------------------------------------------------------------|
| Frontend         | React 18, Vite, React Router, Axios                            |
| Trip Service     | Flask 3, SQLAlchemy, Flask-Migrate (Alembic), Flask-JWT-Extended, marshmallow, gunicorn |
| AI Planner       | Flask 3, pydantic v2, OpenAI SDK / httpx (Ollama), gunicorn    |
| Database         | PostgreSQL 16                                                   |
| Observability    | prometheus-client (`/metrics`), structured JSON logs           |
| Containers       | Multi-stage Docker images, docker-compose                      |

## Repository layout

```
TravelPlanner/
├── frontend/                     # React SPA (+ Dockerfile, nginx.conf)
├── services/
│   ├── trip-service/             # Backend A: Flask + PostgreSQL + JWT
│   └── ai-planner-service/       # Backend B: Flask + OpenAI/Ollama
├── docker-compose.yml            # db + both services + frontend
├── env.example                   # compose env reference (copy to .env)
├── README.md
├── forDevOps.txt                 # ⭐ operations hand-off (env, metrics, security)
├── DEVOPS_ARCHITECTURE.md        # ⭐ K8s/Helm/Terraform/ELK deployment schema
└── instruction.txt               # ⭐ step-by-step staging + prod setup
```

## Quick start (Docker Compose)

Requires Docker + Docker Compose.

```bash
cp env.example .env          # edit secrets; set AI provider (see below)
docker compose up --build
```

| Service           | URL                       |
|-------------------|---------------------------|
| Frontend          | http://localhost:8080     |
| Trip Service API  | http://localhost:5001     |
| AI Planner API    | http://localhost:5002     |
| PostgreSQL        | localhost:5432            |

Migrations run automatically on Trip Service start. Open the frontend, register
an account, create a trip, and click **Plan with AI**.

### Enabling the AI provider

AI planning needs a real LLM (there is no built-in mock). Pick one in `.env`:

- **Ollama (local, free):** install [Ollama](https://ollama.com), `ollama pull llama3.1`,
  then set `AI_PROVIDER=ollama` (default). The container reaches the host at
  `http://host.docker.internal:11434`.
- **OpenAI:** set `AI_PROVIDER=openai` and `OPENAI_API_KEY=sk-...`.

Without a reachable provider, `POST /api/trips/:id/plan` returns **503** and the
UI shows a friendly error — everything else works.

## Local development (without Docker)

You need Python 3.12+, Node 20+, and a PostgreSQL instance.

**Trip Service** (port 5001):
```bash
cd services/trip-service
python -m venv .venv && . .venv/Scripts/activate   # Windows; use bin/activate on *nix
pip install -r requirements-dev.txt
cp env.example .env                                 # set DATABASE_URL etc.
flask db upgrade                                    # apply migrations
flask --app wsgi run --port 5001                    # dev server
```

**AI Planner Service** (port 5002):
```bash
cd services/ai-planner-service
python -m venv .venv && . .venv/Scripts/activate
pip install -r requirements-dev.txt
cp env.example .env                                 # set AI_PROVIDER + creds
flask --app wsgi run --port 5002
```

**Frontend** (port 5173):
```bash
cd frontend
npm install
cp env.example .env                                 # VITE_TRIP_SERVICE_URL=http://localhost:5001
npm run dev
```

## API overview

**Trip Service** (`/api`, JWT required unless noted):

| Method | Path                          | Description                       |
|--------|-------------------------------|-----------------------------------|
| POST   | `/api/auth/register`          | Create account (public)           |
| POST   | `/api/auth/login`             | Log in (public)                   |
| GET    | `/api/auth/me`                | Current user                      |
| GET/PUT| `/api/users/:id`              | Get / update self                 |
| GET    | `/api/trips`                  | List trips (`?status=`,`?saved=`) |
| POST   | `/api/trips`                  | Create trip                       |
| GET/PUT/DELETE | `/api/trips/:id`      | Get / update / delete trip        |
| POST   | `/api/trips/:id/plan`         | Generate itinerary via AI Planner |
| POST   | `/api/trips/:id/save`         | Save / unsave (`/unsave`)         |
| GET    | `/api/trips/:id/itinerary`    | Latest itinerary                  |
| GET    | `/api/services`               | Service registry + health         |

**AI Planner** (internal, `X-Internal-Token` required):

| Method | Path            | Description                          |
|--------|-----------------|--------------------------------------|
| POST   | `/api/plan`     | Generate a structured plan           |
| POST   | `/api/optimize` | Re-optimize an existing plan         |

Both services also expose `GET /health`, `GET /ready`, `GET /metrics`.

## Testing

```bash
# Trip Service (runs on in-memory SQLite; no DB needed)
cd services/trip-service && pip install -r requirements-dev.txt && pytest

# AI Planner (provider is mocked)
cd services/ai-planner-service && pip install -r requirements-dev.txt && pytest

# Frontend
cd frontend && npm install && npm test
```

## Observability

- **Metrics:** `GET /metrics` on both services (Prometheus format). Includes
  standard HTTP metrics plus business metrics (`trips_created_total`,
  `ai_plan_requests_total`, `ai_generation_requests_total`, …).
- **Health:** `GET /health` (liveness), `GET /ready` (readiness — checks DB /
  provider config).
- **Logs:** structured JSON to stdout, ready for ELK / Loki.

See **[forDevOps.txt](forDevOps.txt)** for the metrics catalogue, env-var tables,
scaling and security guidance.
