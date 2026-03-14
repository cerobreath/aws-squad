"""MCP server for SRE Agent Toolkit."""
from mcp.server import FastMCP
from aiops.orchestrator import orchestrate, format_investigation_results
from aiops.config import Config
import logging
import os
import nest_asyncio
nest_asyncio.apply()

# Setup MCP-specific configuration
Config.setup_for_mcp()
logger = logging.getLogger(__name__)

# Initialize MCP server
mcp = FastMCP("SRE Agent Toolkit")


@mcp.tool(
    name="aiops_investigate",
    description="Comprehensive SRE investigation using K8s diagnostics and Grafana observability",
)
def aiops_investigate(
    query: str,
    cluster_name: str = "",
    model_id: str = "eu.anthropic.claude-sonnet-4-20250514-v1:0",
) -> str:
    import asyncio

    resolved_cluster = cluster_name or os.getenv("CLUSTER_NAME", "")
    logger.info(f"AIOps investigating: {query}")
    logger.info(f"Target cluster: {resolved_cluster or '(auto)'}, model: {model_id}")

    try:
        result = asyncio.run(
            orchestrate(query, model_id, cluster_name=resolved_cluster)
        )
        formatted_output = format_investigation_results(result)
        logger.info("AIOps investigation completed successfully")
        return formatted_output

    except Exception as e:
        error_msg = f"AIOps investigation failed: {str(e)}"
        logger.error(error_msg)
        return (
            f"**Error**: {error_msg}\n\n"
            "Please check your Kubernetes access (KUBECONFIG), "
            "Grafana connection (GRAFANA_URL / GRAFANA_API_KEY), "
            "and MCP server availability."
        )


def main():
    """Run the MCP server."""
    try:
        logger.info("Starting SRE Agent Toolkit MCP Server")
        logger.info(f"KUBECONFIG={os.getenv('KUBECONFIG')}")
        mcp.run(transport="stdio")
    except Exception as e:
        logger.error(f"MCP Server failed to start: {e}")
        raise


if __name__ == "__main__":
    main()
