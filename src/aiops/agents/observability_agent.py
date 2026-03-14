"""Grafana MCP client factory for observability operations."""
import logging
import os
from mcp import stdio_client, StdioServerParameters
from strands.tools.mcp.mcp_client import MCPClient

logger = logging.getLogger(__name__)


def get_grafana_mcp_client():
    """Get Grafana MCP client running as a local process via uvx."""
    grafana_url = os.getenv("GRAFANA_URL", "")
    grafana_token = os.getenv("GRAFANA_SERVICE_ACCOUNT_TOKEN", os.getenv("GRAFANA_API_KEY", ""))

    if not grafana_url:
        logger.warning("GRAFANA_URL not set — observability agent will have limited functionality")

    # Pass Grafana env vars explicitly since uvx may not inherit them
    env = {
        **os.environ,
        "GRAFANA_URL": grafana_url,
        "GRAFANA_API_KEY": grafana_token,
    }

    return MCPClient(
        lambda: stdio_client(
            StdioServerParameters(
                command="uvx",
                args=["mcp-grafana"],
                env=env,
                timeout=30,
            )
        )
    )
