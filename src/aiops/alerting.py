"""Alertmanager integration for firing alerts to DevOps.

Supports two modes (auto-detected from ALERTMANAGER_URL):
  1. Direct Alertmanager (Prometheus-style) — POST array to /api/v2/alerts
  2. Grafana built-in alertmanager proxy        — POST {alerts:[…]} to
     /api/alertmanager/<uid>/api/v2/alerts
"""
import logging
import os
from datetime import datetime, timezone
from typing import Optional

import httpx

logger = logging.getLogger(__name__)


class GrafanaAlerter:
    """Fires alerts to Alertmanager (direct or via Grafana proxy)."""

    def __init__(self):
        self._grafana_url = os.getenv("GRAFANA_URL", "http://localhost:3000")
        self._token = os.getenv(
            "GRAFANA_SERVICE_ACCOUNT_TOKEN", os.getenv("GRAFANA_API_KEY", "")
        )

        # If ALERTMANAGER_URL is set, use direct Alertmanager (Prometheus-style).
        # Otherwise proxy through Grafana's built-in alertmanager endpoint.
        self._direct_am_url = os.getenv("ALERTMANAGER_URL", "")
        self._grafana_am_uid = os.getenv("GRAFANA_AM_DATASOURCE_UID", "grafana")

        if self._direct_am_url:
            self._alerts_endpoint = f"{self._direct_am_url.rstrip('/')}/api/v2/alerts"
            self._use_grafana_proxy = False
            logger.info(f"Alerter: direct Alertmanager at {self._alerts_endpoint}")
        else:
            self._alerts_endpoint = (
                f"{self._grafana_url}/api/alertmanager/"
                f"{self._grafana_am_uid}/api/v2/alerts"
            )
            self._use_grafana_proxy = True
            logger.info(f"Alerter: Grafana proxy at {self._alerts_endpoint}")

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
        """Post an alert to Alertmanager.

        Returns True if the alert was accepted, False otherwise.
        """
        now = datetime.now(timezone.utc).isoformat()

        alert_labels = {
            "alertname": "AIOps-Escalation",
            "severity": severity,
            "source": "aiops-daemon",
        }
        if labels:
            alert_labels.update(labels)

        alert_obj = {
            "labels": alert_labels,
            "annotations": {
                "summary": summary,
                "description": description,
            },
            "startsAt": now,
        }

        # Direct Alertmanager expects a JSON array; Grafana proxy expects
        # {"alerts": […]} (PostableAlerts wrapper).
        if self._use_grafana_proxy:
            payload = {"alerts": [alert_obj]}
        else:
            payload = [alert_obj]

        logger.debug(
            f"Firing alert to {self._alerts_endpoint} | "
            f"labels={alert_labels} | proxy={self._use_grafana_proxy}"
        )

        try:
            resp = httpx.post(
                self._alerts_endpoint,
                json=payload,
                headers=self._headers(),
                timeout=10,
            )
            if resp.status_code in (200, 202):
                logger.info(f"Alert fired OK ({resp.status_code}): {summary}")
                return True
            else:
                logger.error(
                    f"Alert rejected ({resp.status_code}): {resp.text}"
                )
                return False
        except Exception as e:
            logger.error(f"Failed to fire alert: {e}")
            return False
