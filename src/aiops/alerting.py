"""Grafana Alertmanager integration for firing alerts to DevOps."""
import logging
import os
from datetime import datetime, timezone
from typing import Optional

import httpx

logger = logging.getLogger(__name__)


class GrafanaAlerter:
    """Fires alerts to Grafana Alertmanager API for DevOps escalation."""

    def __init__(self):
        self._url = os.getenv("GRAFANA_URL", "http://localhost:3000")
        self._token = os.getenv(
            "GRAFANA_SERVICE_ACCOUNT_TOKEN", os.getenv("GRAFANA_API_KEY", "")
        )
        # Alertmanager-compatible endpoint in Grafana
        self._alerts_endpoint = f"{self._url}/api/alertmanager/grafana/api/v2/alerts"

    def _headers(self) -> dict:
        h = {"Content-Type": "application/json"}
        if self._token:
            h["Authorization"] = f"Bearer {self._token}"
        return h

    def fire_alert(
        self,
        summary: str,
        description: str,
        severity: str = "warning",
        labels: Optional[dict] = None,
    ) -> bool:
        """Post an alert to Grafana Alertmanager.

        Args:
            summary: Short one-line summary of the issue.
            description: Full markdown description (LLM analysis).
            severity: "critical", "warning", or "info".
            labels: Extra labels (namespace, service, etc.).

        Returns:
            True if alert was accepted, False otherwise.
        """
        now = datetime.now(timezone.utc).isoformat()

        alert_labels = {
            "alertname": "AIOps-Escalation",
            "severity": severity,
            "source": "aiops-daemon",
        }
        if labels:
            alert_labels.update(labels)

        payload = [
            {
                "labels": alert_labels,
                "annotations": {
                    "summary": summary,
                    "description": description,
                },
                "startsAt": now,
            }
        ]

        try:
            resp = httpx.post(
                self._alerts_endpoint,
                json=payload,
                headers=self._headers(),
                timeout=10,
            )
            if resp.status_code in (200, 202):
                logger.info(f"Alert fired to Grafana: {summary}")
                return True
            else:
                logger.error(
                    f"Grafana alert failed ({resp.status_code}): {resp.text}"
                )
                return False
        except Exception as e:
            logger.error(f"Failed to fire Grafana alert: {e}")
            return False
