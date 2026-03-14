# AIOps Diagnostic Toolkit

AI-powered Kubernetes diagnostics with auto-remediation. Ask questions in plain English, get structured SRE investigation reports. A background daemon continuously monitors cluster health, auto-fixes simple issues, and escalates complex problems to DevOps via Grafana alerts.

Works with any Kubernetes cluster (Minikube, EKS, GKE, AKS, k3s, etc.) and any LLM on Amazon Bedrock.

## How It Works

```
┌──────────────────────────────────────────────────────────────────────┐
│                         AIOps Web App (:8000)                        │
│                                                                      │
│  ┌──────────────┐  POST /api/investigate  ┌───────────────────────┐  │
│  │   Chat UI    │ ─────────────────────── │    Orchestrator       │  │
│  │  (browser)   │ <────────────────────── │  (agent swarm)        │  │
│  └──────────────┘   structured markdown   └──────┬────────┬───────┘  │
│                                                  │        │          │
│  ┌──────────────────────────────┐     ┌──────────┴─┐  ┌───┴───────┐  │
│  │     Health-Check Daemon      │     │ Diagnostic │  │Observabil.│  │
│  │  (every 15 min, configurable)│     │   Agent    │  │  Agent    │  │
│  │                              │     │ kubectl-mcp│  │mcp-grafana│  │
│  │  assess → fix or escalate    │     └────────────┘  └───────────┘  │
│  └──────────┬───────────────────┘                                    │
│             │ unfixable issues                                       │
│             ▼                                                        │
│  ┌──────────────────┐                                                │
│  │ Grafana Alertmgr  │ → Slack / PagerDuty / email / webhook / ...  │
│  └──────────────────┘                                                │
└──────────────────────────────────────────────────────────────────────┘
```

### Interactive investigation
1. Type a question in the web UI (e.g. *"Why are pods crashing in namespace X?"*)
2. The orchestrator optionally runs **cluster discovery** on first use (cached for 1 hour)
3. A **swarm of two AI agents** investigates using real cluster data:
   - **Diagnostic agent** — kubectl-mcp (pods, deployments, events, logs)
   - **Observability agent** — mcp-grafana (dashboards, Prometheus, Loki, alerts)
4. Results come back as a structured report with root cause, evidence, and recommendations

### Health-check daemon
1. Every 15 minutes (configurable), the daemon runs a read-only health assessment
2. If issues are found, each one gets a **suggested fix** (kubectl commands, config changes)
3. Every issue fires a Grafana alert with the problem description and suggested remediation
4. DevOps reviews the suggestion and applies manually — the daemon never modifies the cluster

## Prerequisites

- **Python 3.12+**
- **Kubernetes cluster** with a valid kubeconfig (any distro)
- **Grafana** instance with a service account token (Editor role for alerting)
- **AWS Bedrock access** for the LLM (any supported model)
- **kubectl-mcp-server** installed (`pip install kubectl-mcp-server`)

## Setup

### 1. Kubernetes

```bash
kubectl cluster-info
kubectl get namespaces
```

For Minikube:
```bash
minikube start
kubectl create namespace demo
kubectl -n demo create deployment nginx --image=nginx --replicas=3
```

### 2. Grafana

You need a running Grafana instance and a service account token.

```bash
docker compose up -d grafana prometheus
# Grafana at http://localhost:3000
```

Create a service account token (Editor role for alerting):
```bash
SA=$(curl -s -X POST http://admin:PASSWORD@localhost:3000/api/serviceaccounts \
  -H 'Content-Type: application/json' -d '{"name":"aiops","role":"Editor"}')
SA_ID=$(echo "$SA" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
curl -s -X POST "http://admin:PASSWORD@localhost:3000/api/serviceaccounts/$SA_ID/tokens" \
  -H 'Content-Type: application/json' -d '{"name":"aiops-token"}'
```

For alert routing setup (Slack, PagerDuty, email, webhook, etc.), see **[ALERTS.md](ALERTS.md)**.

### 3. AWS Bedrock

Make sure you have AWS credentials configured and `bedrock:InvokeModel` permission.

Supported models (select in the UI):
| Model | Region | Notes |
|-------|--------|-------|
| Amazon Nova Pro | us-east-1 | Default, fast, no approval needed |
| DeepSeek V3.2 | us-east-1 | Slower with many tools |
| Claude Sonnet 4 | eu-west-1 | Needs Anthropic use-case approval |
| Claude Haiku 4.5 | eu-west-1 | Needs Anthropic use-case approval |

### 4. Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `KUBECONFIG` | No | `~/.kube/config` | Path to kubeconfig file |
| `CLUSTER_NAME` | No | — | Cluster name for auto-discovery caching |
| `GRAFANA_URL` | **Yes** | — | Grafana instance URL |
| `GRAFANA_SERVICE_ACCOUNT_TOKEN` | **Yes** | — | Grafana SA token (Editor role) |
| **Daemon** | | | |
| `AIOPS_DAEMON_ENABLED` | No | `true` | Auto-start health daemon |
| `AIOPS_HEALTH_CHECK_INTERVAL` | No | `900` | Seconds between checks (900 = 15 min) |
| `AIOPS_DAEMON_MODEL` | No | `amazon.nova-pro-v1:0` | Bedrock model for daemon |
| **Optional** | | | |
| `AIOPS_PROFILE_TTL_SECONDS` | No | `3600` | Cluster profile cache TTL |
| `OTEL_SDK_DISABLED` | No | — | Set to `true` to disable OTLP tracing |
| `LANGFUSE_PUBLIC_KEY` | No | — | Langfuse tracing |
| `LANGFUSE_SECRET_KEY` | No | — | Langfuse tracing |

## Running

### Local

```bash
cd aiops
pip install -r requirements.txt
pip install kubectl-mcp-server

export GRAFANA_URL=http://localhost:3000
export GRAFANA_SERVICE_ACCOUNT_TOKEN=glsa_xxxxx
export CLUSTER_NAME=minikube
export OTEL_SDK_DISABLED=true

# Run from parent directory so 'aiops' is importable as a package
cd ..
uvicorn aiops.web:app --host 0.0.0.0 --port 8000
```

Open http://localhost:8000. The daemon starts automatically and the status bar appears at the top of the UI.

### Docker

```bash
cd aiops
docker build -t aiops .

docker run -p 8000:8000 \
  -e GRAFANA_URL=http://host.docker.internal:3000 \
  -e GRAFANA_SERVICE_ACCOUNT_TOKEN=glsa_xxxxx \
  -e CLUSTER_NAME=minikube \
  -v ~/.kube/config:/root/.kube/config:ro \
  -v ~/.aws:/root/.aws:ro \
  aiops
```

### Docker Compose

```yaml
services:
  aiops:
    build: ./aiops
    ports:
      - "8000:8000"
    environment:
      GRAFANA_URL: http://grafana:3000
      GRAFANA_SERVICE_ACCOUNT_TOKEN: ${GRAFANA_TOKEN}
      CLUSTER_NAME: ${CLUSTER_NAME:-}
      AIOPS_HEALTH_CHECK_INTERVAL: "900"
      OTEL_SDK_DISABLED: "true"
    volumes:
      - ~/.kube/config:/root/.kube/config:ro
      - ~/.aws:/root/.aws:ro
    depends_on:
      - grafana
```

### AWS Fargate

1. Push image to ECR
2. Create Fargate task definition:
   - Container port: `8000`
   - Health check: `/health`
   - Task IAM role with `bedrock:InvokeModel`
   - Inject `GRAFANA_URL`, `GRAFANA_SERVICE_ACCOUNT_TOKEN` from Secrets Manager
3. Create ECS service behind ALB targeting port `8000`

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | Web UI |
| `/health` | GET | Health check |
| `/api/investigate` | POST | Run investigation (query, cluster_name, model_id) |
| `/api/daemon/status` | GET | Daemon state, counters, last check |
| `/api/daemon/history` | GET | Last 50 health check results |
| `/api/daemon/start` | POST | Start daemon manually |
| `/api/daemon/stop` | POST | Stop daemon |

## Project Structure

```
aiops/
├── agents/
│   ├── diagnostic_agent.py    # kubectl-mcp client
│   └── observability_agent.py # mcp-grafana client
├── static/
│   └── index.html             # Chat UI + daemon status bar
├── alerting.py                # Grafana Alertmanager integration
├── cluster_profile.py         # In-memory cluster topology cache
├── config.py                  # Logging, telemetry, env setup
├── daemon.py                  # Health-check daemon (assess → fix → escalate)
├── orchestrator.py            # Agent swarm coordination
├── prompts.py                 # System prompts for all agents
├── mcp_server.py              # MCP server entry point (for Amazon Q)
├── web.py                     # FastAPI app + daemon lifecycle
├── Dockerfile
├── requirements.txt
├── README.md                  # This file
└── ALERTS.md                  # Grafana alerting setup guide
```

## MCP Server Mode

The toolkit can also run as an MCP server for Amazon Q Developer or any MCP client:

```json
{
  "mcpServers": {
    "aiops": {
      "command": "python",
      "args": ["-m", "aiops.mcp_server"],
      "env": {
        "GRAFANA_URL": "http://localhost:3000",
        "GRAFANA_SERVICE_ACCOUNT_TOKEN": "glsa_xxxxx"
      }
    }
  }
}
```
