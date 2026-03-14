"""SRE Agent Orchestrator for coordinating specialized agents."""
import logging
import os
from contextlib import contextmanager
from datetime import datetime

from strands import Agent
from strands.models import BedrockModel
from strands.multiagent.swarm import Swarm

from aiops.agents.diagnostic_agent import get_k8s_mcp_client
from aiops.agents.observability_agent import get_grafana_mcp_client
from aiops.cluster_profile import ClusterProfile
from aiops.prompts import (
    CLUSTER_DISCOVERY_PROMPT,
    DIAGNOSTIC_AGENT_SWARM_PROMPT,
    OBSERVABILITY_AGENT_SWARM_PROMPT,
)

# Only expose essential diagnostic tools to the LLM (235 is too many)
DIAGNOSTIC_TOOLS = {
    "get_pods", "get_deployments", "get_services", "get_namespaces",
    "get_nodes", "get_events", "get_logs", "get_previous_logs",
    "get_configmaps", "get_endpoints", "get_ingress", "get_daemonsets",
    "get_statefulsets", "get_replicasets", "get_jobs", "get_hpa", "get_pvcs",
    "get_persistent_volumes", "get_node_metrics", "get_pod_metrics",
    "get_resource_usage", "get_cluster_info", "get_current_context",
    "kubectl_describe", "kubectl_explain",
    "get_pod_events", "get_pod_conditions", "check_pod_health",
    "diagnose_pod_crash", "diagnose_network_connectivity",
    "detect_pending_pods", "get_evicted_pods", "health_check",
    "switch_context", "get_secrets", "get_pod_security_info",
}

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Langfuse is optional — tracing works when configured, silently skipped otherwise
# ---------------------------------------------------------------------------
try:
    from langfuse import get_client as _get_langfuse_client

    def _langfuse_available() -> bool:
        return bool(
            os.getenv("LANGFUSE_PUBLIC_KEY") and os.getenv("LANGFUSE_SECRET_KEY")
        )

except ImportError:
    _get_langfuse_client = None  # type: ignore[assignment]

    def _langfuse_available() -> bool:
        return False


@contextmanager
def _tracing_span(name: str, input_data: dict):
    """Yield a span-like object if Langfuse is available, else a no-op."""
    if _langfuse_available() and _get_langfuse_client is not None:
        langfuse = _get_langfuse_client()
        with langfuse.start_as_current_span(name=name, input=input_data) as span:
            yield span
    else:
        # No-op context: expose a minimal duck-typed span
        class _NoOpSpan:
            def update(self, **_kw):
                pass

        yield _NoOpSpan()


def format_investigation_results(result: dict) -> str:
    """Format investigation results for display."""
    if isinstance(result, dict):
        formatted_output = "## SRE Investigation Results\n\n"
        for agent_name, agent_result in result.items():
            formatted_output += f"### {agent_name.replace('_', ' ').title()}\n"
            formatted_output += f"{agent_result}\n\n"
        return formatted_output
    return str(result)


def _discover_cluster(cluster_name: str, diagnostic_tools, model) -> str:
    """Run a single-turn discovery agent to profile the cluster."""
    logger.info(f"Running cluster discovery for '{cluster_name}'")
    discovery_agent = Agent(
        name="cluster_discovery",
        model=model,
        system_prompt=CLUSTER_DISCOVERY_PROMPT,
        tools=diagnostic_tools,
    )
    result = discovery_agent(
        f"Discover and summarise the topology of the Kubernetes cluster '{cluster_name}'."
    )
    return str(getattr(result, "content", result))


async def orchestrate(
    query: str,
    model_id: str = "eu.anthropic.claude-sonnet-4-20250514-v1:0",
    cluster_name: str = "",
):
    """Orchestrate a comprehensive investigation using specialized agents.

    Args:
        query: The investigation query
        model_id: Bedrock model ID to use for all agents
        cluster_name: Kubernetes cluster name (falls back to CLUSTER_NAME env var)
    """
    logger.info(f"Starting orchestration for query: {query}")
    logger.info(f"Using model: {model_id}")

    with _tracing_span(
        "aiops-investigation",
        {"query": query, "model_id": model_id, "cluster_name": cluster_name},
    ) as span:
        try:
            k8s_client = get_k8s_mcp_client()
            grafana_client = get_grafana_mcp_client()

            with k8s_client, grafana_client:
                all_k8s_tools = k8s_client.list_tools_sync()
                grafana_tools = grafana_client.list_tools_sync()

                # Filter to essential diagnostic tools (full set overwhelms most LLMs)
                k8s_tools = [
                    t for t in all_k8s_tools
                    if getattr(t, "tool_name", getattr(t, "name", "")) in DIAGNOSTIC_TOOLS
                ]
                logger.info(
                    f"Using {len(k8s_tools)}/{len(all_k8s_tools)} K8s tools, "
                    f"{len(grafana_tools)} Grafana tools"
                )

                # Route to correct region per model
                bedrock_kwargs = {"model_id": model_id}
                if "deepseek" in model_id or "amazon.nova" in model_id:
                    bedrock_kwargs["region_name"] = "us-east-1"
                model = BedrockModel(**bedrock_kwargs)

                # --- Cluster profile resolution ---
                cluster_context = ""
                if cluster_name:
                    profile_store = ClusterProfile()
                    cached = profile_store.get_profile(cluster_name)
                    if cached:
                        cluster_context = cached
                    else:
                        cluster_context = _discover_cluster(
                            cluster_name, k8s_tools, model
                        )
                        profile_store.save_profile(cluster_name, cluster_context)

                diagnostic_prompt = DIAGNOSTIC_AGENT_SWARM_PROMPT.format(
                    cluster_context=cluster_context
                )

                session_id = f"aiops-{hash(query) % 10000}"

                diagnostic_agent = Agent(
                    name="diagnostic_agent",
                    model=model,
                    system_prompt=diagnostic_prompt,
                    tools=k8s_tools,
                    trace_attributes={
                        "session.id": session_id,
                        "user.id": "AIOps",
                        "agent.type": "diagnostic",
                        "model.id": model_id,
                        "trace.name": "AIOps-Diagnostics",
                        "langfuse.tags": [
                            "AIOps-K8s",
                            "Diagnostics",
                            "Agent-Swarm",
                        ],
                    },
                )

                observability_agent = Agent(
                    name="observability_agent",
                    model=model,
                    system_prompt=OBSERVABILITY_AGENT_SWARM_PROMPT,
                    tools=grafana_tools,
                    trace_attributes={
                        "session.id": session_id,
                        "user.id": "AIOps",
                        "agent.type": "observability",
                        "model.id": model_id,
                        "trace.name": "AIOps-Observability",
                        "langfuse.tags": [
                            "AIOps-K8s",
                            "Observability",
                            "Agent-Swarm",
                        ],
                    },
                )

                swarm = Swarm([diagnostic_agent, observability_agent])
                logger.info("Running SRE swarm analysis...")

                current_time = datetime.now().strftime(
                    "%A, %Y-%m-%d %H:%M:%S UTC"
                )
                enhanced_query = (
                    f"Current time: {current_time}\n\nUser query: {query}"
                )

                result = await swarm.invoke_async(enhanced_query)

            final_result = {
                "status": "success",
                "query": query,
                "swarm_status": result.status.value,
                "execution_time": result.execution_time,
                "agents_used": [node.node_id for node in result.node_history],
                "results": {
                    name: getattr(node_result.result, "content", str(node_result.result))
                    for name, node_result in result.results.items()
                },
            }

            formatted_output = format_investigation_results(final_result["results"])
            logger.info(
                f"Formatted output length: {len(formatted_output)} characters"
            )
            span.update(output=formatted_output)

            return final_result["results"]

        except Exception as e:
            logger.error(f"Orchestration failed: {str(e)}")
            span.update(output=f"Error: {str(e)}")
            raise
