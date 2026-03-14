# Grafana Alerting Setup for AIOps Daemon

The AIOps health-check daemon fires alerts to Grafana's built-in Alertmanager when it detects issues that can't be auto-fixed. This document explains how to configure Grafana to receive and route those alerts to your team.

## How It Works

```
Daemon detects unfixable issue
  → POST /api/alertmanager/grafana/api/v2/alerts
    → Grafana Alertmanager receives alert
      → Notification policy matches labels
        → Contact point delivers notification (Slack, PagerDuty, email, webhook, etc.)
```

The daemon sends alerts with these labels:
- `alertname: AIOps-Escalation`
- `severity: critical | warning | info`
- `source: aiops-daemon`
- `namespace: <k8s namespace>` (when applicable)
- `resource: <pod/deployment name>` (when applicable)

## Configuration Methods

Grafana supports two ways to configure alerting: **provisioning files** (recommended for reproducible deployments) and **HTTP API** (for dynamic/programmatic setup). Both are documented below.

---

## Method 1: Provisioning Files (Recommended)

Provisioning files are YAML configs loaded by Grafana on startup. They're ideal for Docker, Kubernetes, and infrastructure-as-code setups.

### Directory Structure

```
grafana/provisioning/
├── datasources/
│   └── datasources.yml
├── dashboards/
│   └── dashboards.yml
└── alerting/
    └── alerting.yml       ← add this
```

Mount this directory to `/etc/grafana/provisioning` in your Grafana container.

### Contact Point Examples

Create `grafana/provisioning/alerting/alerting.yml`:

#### Slack

```yaml
apiVersion: 1

contactPoints:
  - orgId: 1
    name: slack-devops
    receivers:
      - uid: slack-1
        type: slack
        settings:
          url: https://hooks.slack.com/services/YOUR/WEBHOOK/URL
          # Optional overrides:
          # channel: "#alerts"
          # username: "AIOps Bot"
          # title: |
          #   {{ .CommonLabels.alertname }}
          # text: |
          #   {{ .CommonAnnotations.summary }}
          #   {{ .CommonAnnotations.description }}

policies:
  - orgId: 1
    receiver: slack-devops
    # Route all AIOps alerts to this contact point
    routes:
      - receiver: slack-devops
        matchers:
          - alertname = AIOps-Escalation
        continue: false
```

#### Webhook (Generic HTTP)

```yaml
apiVersion: 1

contactPoints:
  - orgId: 1
    name: webhook-devops
    receivers:
      - uid: webhook-1
        type: webhook
        settings:
          url: https://your-service.example.com/alerts
          httpMethod: POST
          # Optional: add auth header
          # authorization_scheme: Bearer
          # authorization_credentials: your-token

policies:
  - orgId: 1
    receiver: webhook-devops
    routes:
      - receiver: webhook-devops
        matchers:
          - alertname = AIOps-Escalation
```

#### PagerDuty

```yaml
apiVersion: 1

contactPoints:
  - orgId: 1
    name: pagerduty-devops
    receivers:
      - uid: pd-1
        type: pagerduty
        settings:
          integrationKey: YOUR_PAGERDUTY_INTEGRATION_KEY
          severity: '{{ .CommonLabels.severity }}'
          # class: kubernetes
          # component: aiops

policies:
  - orgId: 1
    receiver: pagerduty-devops
    routes:
      - receiver: pagerduty-devops
        matchers:
          - alertname = AIOps-Escalation
          - severity = critical
```

#### Email

Requires SMTP configured in `grafana.ini` or env vars:

```ini
# grafana.ini or via env vars (GF_SMTP_*)
[smtp]
enabled = true
host = smtp.gmail.com:587
user = alerts@yourcompany.com
password = app-password
from_address = alerts@yourcompany.com
```

```yaml
apiVersion: 1

contactPoints:
  - orgId: 1
    name: email-devops
    receivers:
      - uid: email-1
        type: email
        settings:
          addresses: oncall@yourcompany.com;sre-team@yourcompany.com
          singleEmail: false

policies:
  - orgId: 1
    receiver: email-devops
    routes:
      - receiver: email-devops
        matchers:
          - alertname = AIOps-Escalation
```

#### Telegram

```yaml
apiVersion: 1

contactPoints:
  - orgId: 1
    name: telegram-devops
    receivers:
      - uid: tg-1
        type: telegram
        settings:
          bottoken: "YOUR_BOT_TOKEN"
          chatid: "YOUR_CHAT_ID"
          # message: |
          #   *{{ .CommonLabels.alertname }}*
          #   {{ .CommonAnnotations.summary }}
```

#### Discord

```yaml
apiVersion: 1

contactPoints:
  - orgId: 1
    name: discord-devops
    receivers:
      - uid: discord-1
        type: discord
        settings:
          url: https://discord.com/api/webhooks/YOUR/WEBHOOK/URL
```

#### Microsoft Teams

```yaml
apiVersion: 1

contactPoints:
  - orgId: 1
    name: teams-devops
    receivers:
      - uid: teams-1
        type: teams
        settings:
          url: https://outlook.office.com/webhook/YOUR/WEBHOOK/URL
```

### Multiple Contact Points

You can route by severity:

```yaml
apiVersion: 1

contactPoints:
  - orgId: 1
    name: slack-warnings
    receivers:
      - uid: slack-warn
        type: slack
        settings:
          url: https://hooks.slack.com/services/WARNINGS/WEBHOOK

  - orgId: 1
    name: pagerduty-critical
    receivers:
      - uid: pd-crit
        type: pagerduty
        settings:
          integrationKey: YOUR_PD_KEY

policies:
  - orgId: 1
    receiver: slack-warnings
    routes:
      - receiver: pagerduty-critical
        matchers:
          - alertname = AIOps-Escalation
          - severity = critical
      - receiver: slack-warnings
        matchers:
          - alertname = AIOps-Escalation
          - severity =~ warning|info
```

### Docker Compose Example

```yaml
services:
  grafana:
    image: grafana/grafana:11.5.2
    volumes:
      - ./grafana/provisioning:/etc/grafana/provisioning
      - ./grafana/dashboards:/var/lib/grafana/dashboards
    environment:
      GF_SECURITY_ADMIN_USER: admin
      GF_SECURITY_ADMIN_PASSWORD: changeme
      # For email alerts:
      # GF_SMTP_ENABLED: "true"
      # GF_SMTP_HOST: smtp.gmail.com:587
      # GF_SMTP_USER: alerts@yourcompany.com
      # GF_SMTP_PASSWORD: app-password
    ports:
      - "3000:3000"
```

---

## Method 2: HTTP API

Use this for dynamic environments where you need to create contact points at runtime.

### Prerequisites

- Grafana service account token with **Editor** or **Admin** role
- `GRAFANA_URL` and token available

### Create a Contact Point

```bash
# Slack example
curl -s -X POST "${GRAFANA_URL}/api/v1/provisioning/contact-points" \
  -H "Authorization: Bearer ${GRAFANA_TOKEN}" \
  -H "Content-Type: application/json" \
  -H "X-Disable-Provenance: true" \
  -d '{
    "name": "slack-devops",
    "type": "slack",
    "settings": {
      "url": "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
    }
  }'
```

```bash
# Webhook example
curl -s -X POST "${GRAFANA_URL}/api/v1/provisioning/contact-points" \
  -H "Authorization: Bearer ${GRAFANA_TOKEN}" \
  -H "Content-Type: application/json" \
  -H "X-Disable-Provenance: true" \
  -d '{
    "name": "webhook-devops",
    "type": "webhook",
    "settings": {
      "url": "https://your-service.example.com/alerts",
      "httpMethod": "POST"
    }
  }'
```

### Set Notification Policy

```bash
curl -s -X PUT "${GRAFANA_URL}/api/v1/provisioning/policies" \
  -H "Authorization: Bearer ${GRAFANA_TOKEN}" \
  -H "Content-Type: application/json" \
  -H "X-Disable-Provenance: true" \
  -d '{
    "receiver": "slack-devops",
    "routes": [
      {
        "receiver": "slack-devops",
        "matchers": ["alertname = AIOps-Escalation"]
      }
    ]
  }'
```

### Test a Contact Point

```bash
curl -s -X POST "${GRAFANA_URL}/api/alertmanager/grafana/config/api/v1/receivers/test" \
  -H "Authorization: Bearer ${GRAFANA_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "receivers": [{
      "name": "slack-devops",
      "grafana_managed_receiver_configs": [{
        "type": "slack",
        "settings": {
          "url": "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
        }
      }]
    }]
  }'
```

### List Existing Contact Points

```bash
curl -s "${GRAFANA_URL}/api/v1/provisioning/contact-points" \
  -H "Authorization: Bearer ${GRAFANA_TOKEN}" | python3 -m json.tool
```

---

## Verify It Works

### 1. Check Grafana loaded the config

```bash
# List contact points
curl -s http://localhost:3000/api/v1/provisioning/contact-points \
  -H "Authorization: Bearer YOUR_TOKEN" | python3 -m json.tool
```

### 2. Fire a test alert manually

```bash
curl -s -X POST http://localhost:3000/api/alertmanager/grafana/api/v2/alerts \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '[{
    "labels": {
      "alertname": "AIOps-Escalation",
      "severity": "warning",
      "source": "aiops-daemon-test"
    },
    "annotations": {
      "summary": "[TEST] AIOps daemon test alert",
      "description": "This is a test alert from AIOps. If you see this, alerting is configured correctly."
    }
  }]'
```

### 3. Check daemon status

```bash
curl -s http://localhost:8000/api/daemon/status | python3 -m json.tool
```

Look for `alerts_fired > 0` to confirm the daemon is sending alerts.

### 4. View alert history

```bash
curl -s http://localhost:8000/api/daemon/history | python3 -m json.tool
```

---

## Daemon Configuration Reference

| Env var | Default | Description |
|---------|---------|-------------|
| `AIOPS_DAEMON_ENABLED` | `true` | Auto-start daemon with the web app |
| `AIOPS_HEALTH_CHECK_INTERVAL` | `900` | Seconds between health checks (900 = 15 min) |
| `AIOPS_DAEMON_MODEL` | `amazon.nova-pro-v1:0` | Bedrock model ID for health checks |
| `GRAFANA_URL` | `http://localhost:3000` | Grafana instance URL |
| `GRAFANA_SERVICE_ACCOUNT_TOKEN` | — | Grafana SA token (Editor role for alerting) |

## Grafana Service Account Permissions

For the daemon to fire alerts, the Grafana service account needs **Editor** role (not just Viewer). You can create one via:

**Provisioning (grafana.ini):**
```ini
# Not supported — use API or UI to create service accounts
```

**API:**
```bash
# Create service account
SA=$(curl -s -X POST http://admin:PASSWORD@localhost:3000/api/serviceaccounts \
  -H 'Content-Type: application/json' \
  -d '{"name":"aiops-daemon","role":"Editor"}')
SA_ID=$(echo "$SA" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")

# Create token
curl -s -X POST "http://admin:PASSWORD@localhost:3000/api/serviceaccounts/$SA_ID/tokens" \
  -H 'Content-Type: application/json' \
  -d '{"name":"aiops-daemon-token"}'
```

Use the `key` value from the response as `GRAFANA_SERVICE_ACCOUNT_TOKEN`.
