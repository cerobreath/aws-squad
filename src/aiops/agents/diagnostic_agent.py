"""Kubernetes MCP client factory for diagnostic operations."""
import logging
import shutil
import sys
from pathlib import Path
from mcp import stdio_client, StdioServerParameters
from strands.tools.mcp.mcp_client import MCPClient

logger = logging.getLogger(__name__)


def get_k8s_mcp_client():
    """Get Kubernetes MCP client running as a local process."""
    cmd = shutil.which("kubectl-mcp")
    if not cmd:
        venv_bin = Path(sys.executable).parent / "kubectl-mcp"
        if venv_bin.exists():
            cmd = str(venv_bin)
    if not cmd:
        raise RuntimeError("kubectl-mcp not found on PATH. Install with: pip install kubectl-mcp-server")
    logger.info(f"Using kubectl-mcp at: {cmd}")
    return MCPClient(
        lambda: stdio_client(
            StdioServerParameters(
                command=cmd,
                args=[],
                timeout=60,
            )
        )
    )
