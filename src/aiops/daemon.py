"""Health-check daemon — periodic cluster monitoring with alert escalation."""
import asyncio
import json
import logging
import os
import threading
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Optional

from strands import Agent
from strands.models import BedrockModel

from aiops.agents.diagnostic_agent import get_k8s_mcp_client
from aiops.alerting import GrafanaAlerter
from aiops.orchestrator import DIAGNOSTIC_TOOLS
from aiops.prompts import HEALTH_CHECK_PROMPT

logger = logging.getLogger(__name__)


@dataclass
class DaemonState:
    """Observable state of the health-check daemon."""

    running: bool = False
    last_check: Optional[str] = None
    last_status: Optional[str] = None  # "healthy" | "unhealthy" | "error"
    last_summary: Optional[str] = None
    checks_total: int = 0
    issues_found: int = 0
    alerts_fired: int = 0
    history: list = field(default_factory=list)  # last N check results


class HealthDaemon:
    """Background daemon that periodically checks cluster health and sends
    all findings as Grafana alerts with suggested remediation steps.
    The daemon never modifies the cluster — it only observes and reports."""

    def __init__(self):
        self._interval = int(os.getenv("AIOPS_HEALTH_CHECK_INTERVAL", "900"))  # 15 min
        self._model_id = os.getenv("AIOPS_DAEMON_MODEL", "amazon.nova-pro-v1:0")
        self._cluster_name = os.getenv("CLUSTER_NAME", "")
        self._max_history = 50
        self._thread: Optional[threading.Thread] = None
        self._stop_event = threading.Event()
        self._alerter = GrafanaAlerter()
        self.state = DaemonState()

    # ------------------------------------------------------------------
    # Lifecycle
    # ------------------------------------------------------------------

    def start(self) -> None:
        if self.state.running:
            logger.warning("Health daemon already running")
            return
        self._stop_event.clear()
        self._thread = threading.Thread(target=self._loop, daemon=True, name="health-daemon")
        self._thread.start()
        self.state.running = True
        logger.info(
            f"Health daemon started (interval={self._interval}s, model={self._model_id})"
        )

    def stop(self) -> None:
        if not self.state.running:
            return
        self._stop_event.set()
        if self._thread:
            self._thread.join(timeout=30)
        self.state.running = False
        logger.info("Health daemon stopped")

    # ------------------------------------------------------------------
    # Main loop
    # ------------------------------------------------------------------

    def _loop(self) -> None:
        self._run_check()
        while not self._stop_event.is_set():
            self._stop_event.wait(timeout=self._interval)
            if self._stop_event.is_set():
                break
            self._run_check()

    def _run_check(self) -> None:
        now = datetime.now(timezone.utc).isoformat()
        self.state.last_check = now
        self.state.checks_total += 1
        logger.info(f"[daemon] Health check #{self.state.checks_total} starting at {now}")

        try:
            result = asyncio.run(self._assess_health())
            logger.info(f"[daemon] Raw assessment result: {json.dumps(result, default=str)[:500]}")
            self._process_result(result, now)
        except Exception as e:
            logger.error(f"[daemon] Health check failed: {e}", exc_info=True)
            self.state.last_status = "error"
            self.state.last_summary = str(e)
            self._append_history(now, "error", str(e), [])

    # ------------------------------------------------------------------
    # Health assessment (read-only)
    # ------------------------------------------------------------------

    async def _assess_health(self) -> dict:
        k8s_client = get_k8s_mcp_client()
        with k8s_client:
            all_tools = k8s_client.list_tools_sync()
            tools = [
                t for t in all_tools
                if getattr(t, "tool_name", getattr(t, "name", "")) in DIAGNOSTIC_TOOLS
            ]

            bedrock_kwargs = {"model_id": self._model_id}
            if "deepseek" in self._model_id or "amazon.nova" in self._model_id:
                bedrock_kwargs["region_name"] = "us-east-1"
            model = BedrockModel(**bedrock_kwargs)

            agent = Agent(
                name="health_checker",
                model=model,
                system_prompt=HEALTH_CHECK_PROMPT,
                tools=tools,
            )
            result = agent(
                f"Check the health of the Kubernetes cluster"
                f"{' ' + self._cluster_name if self._cluster_name else ''}. "
                f"Current time: {datetime.now(timezone.utc).isoformat()}"
            )
            raw = str(getattr(result, "content", result))

        return self._parse_json(raw)

    # ------------------------------------------------------------------
    # Process results — send alerts with suggestions for every issue
    # ------------------------------------------------------------------

    def _process_result(self, result: dict, timestamp: str) -> None:
        healthy = result.get("healthy", True)
        issues = result.get("issues", [])
        summary = result.get("summary", "No summary")

        self.state.last_status = "healthy" if healthy else "unhealthy"
        self.state.last_summary = summary
        self.state.issues_found += len(issues)

        logger.info(
            f"[daemon] Cluster {'HEALTHY' if healthy else 'UNHEALTHY'}: {summary} "
            f"({len(issues)} issues)"
        )

        if healthy:
            self._append_history(timestamp, "healthy", summary, [])
            return

        alerts_sent = []
        for issue in issues:
            fired = self._send_alert(issue)
            alerts_sent.append({"issue": issue.get("problem", ""), "alerted": fired})

        self._append_history(timestamp, "unhealthy", summary, alerts_sent)

    def _send_alert(self, issue: dict) -> bool:
        """Send a Grafana alert with the issue details and suggested fix."""
        severity = issue.get("severity", "warning")
        resource = issue.get("resource", "unknown")
        namespace = issue.get("namespace", "")
        problem = issue.get("problem", "Unknown issue")
        suggestion = issue.get("suggested_fix", "No suggestion available")

        summary = f"[AIOps] {severity.upper()}: {problem}"
        description = (
            f"**Resource:** `{resource}`\n"
            f"**Namespace:** `{namespace}`\n"
            f"**Problem:** {problem}\n"
            f"**Severity:** {severity}\n\n"
            f"### Suggested Fix\n{suggestion}\n\n"
            f"*This alert was generated by the AIOps health-check daemon. "
            f"Review the suggestion and apply manually if appropriate.*"
        )

        labels = {"severity": severity}
        if namespace:
            labels["namespace"] = namespace
        if resource:
            labels["resource"] = resource

        fired = self._alerter.fire_alert(
            summary=summary,
            description=description,
            severity=severity,
            labels=labels,
        )
        if fired:
            self.state.alerts_fired += 1
        logger.info(f"[daemon] Alert sent (fired={fired}): {summary}")
        return fired

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    def _append_history(
        self, timestamp: str, status: str, summary: str, actions: list
    ) -> None:
        entry = {
            "timestamp": timestamp,
            "status": status,
            "summary": summary,
            "actions": actions,
        }
        self.state.history.append(entry)
        if len(self.state.history) > self._max_history:
            self.state.history = self.state.history[-self._max_history:]

    @staticmethod
    def _parse_json(raw: str) -> dict:
        """Extract JSON from LLM output that may contain markdown fences."""
        text = raw.strip()
        if "```" in text:
            parts = text.split("```")
            for part in parts:
                part = part.strip()
                if part.startswith("json"):
                    part = part[4:].strip()
                if part.startswith("{"):
                    text = part
                    break
        try:
            return json.loads(text)
        except json.JSONDecodeError:
            start = text.find("{")
            end = text.rfind("}") + 1
            if start >= 0 and end > start:
                try:
                    return json.loads(text[start:end])
                except json.JSONDecodeError:
                    pass
            logger.warning(f"[daemon] Could not parse LLM output as JSON: {text[:200]}")
            return {"healthy": False, "issues": [], "summary": f"Parse error: {text[:100]}"}
