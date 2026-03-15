"""FastAPI web UI for AIOps diagnostic toolkit."""
import asyncio
import logging
import os
from pathlib import Path

from fastapi import FastAPI
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

from aiops.config import Config
from aiops.daemon import HealthDaemon
from aiops.orchestrator import orchestrate, format_investigation_results

Config.setup_for_development()
logger = logging.getLogger(__name__)

app = FastAPI(title="AIOps Diagnostic Toolkit")
daemon = HealthDaemon()

STATIC_DIR = Path(__file__).parent / "static"
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")


# ------------------------------------------------------------------
# Lifecycle — start/stop daemon with the app
# ------------------------------------------------------------------

@app.on_event("startup")
async def on_startup():
    if os.getenv("AIOPS_DAEMON_ENABLED", "true").lower() in ("true", "1", "yes"):
        daemon.start()


@app.on_event("shutdown")
async def on_shutdown():
    daemon.stop()


# ------------------------------------------------------------------
# Models
# ------------------------------------------------------------------

class InvestigateRequest(BaseModel):
    query: str
    cluster_name: str = ""
    model_id: str = "amazon.nova-pro-v1:0"


class InvestigateResponse(BaseModel):
    status: str
    result: str


# ------------------------------------------------------------------
# Routes
# ------------------------------------------------------------------

def _run_orchestrate(query: str, model_id: str, cluster_name: str) -> dict:
    """Run orchestration in a separate event loop (blocking)."""
    return asyncio.run(orchestrate(query, model_id, cluster_name=cluster_name))


@app.get("/", response_class=HTMLResponse)
async def index():
    return (STATIC_DIR / "index.html").read_text()


@app.post("/api/investigate", response_model=InvestigateResponse)
async def investigate(req: InvestigateRequest):
    cluster = req.cluster_name or os.getenv("CLUSTER_NAME", "")
    logger.info(f"Investigation request: query={req.query!r}, cluster={cluster!r}")

    try:
        result = await asyncio.to_thread(
            _run_orchestrate, req.query, req.model_id, cluster
        )
        formatted = format_investigation_results(result)
        return InvestigateResponse(status="success", result=formatted)
    except Exception as e:
        logger.error(f"Investigation failed: {e}")
        return InvestigateResponse(
            status="error", result=f"Investigation failed: {e}"
        )


@app.get("/health")
async def health():
    return {"status": "healthy"}


# ------------------------------------------------------------------
# Daemon control & status
# ------------------------------------------------------------------

@app.get("/api/daemon/status")
async def daemon_status():
    s = daemon.state
    return {
        "running": s.running,
        "interval_seconds": daemon._interval,
        "model": daemon._model_id,
        "last_check": s.last_check,
        "last_status": s.last_status,
        "last_summary": s.last_summary,
        "checks_total": s.checks_total,
        "issues_found": s.issues_found,
        "alerts_fired": s.alerts_fired,
    }


@app.get("/api/daemon/history")
async def daemon_history():
    return {"history": daemon.state.history}


@app.post("/api/daemon/start")
async def daemon_start():
    daemon.start()
    return {"status": "started"}


@app.post("/api/daemon/stop")
async def daemon_stop():
    daemon.stop()
    return {"status": "stopped"}
