"""Configuration management for AIOps SRE toolkit."""
import logging
import os
import base64
from pathlib import Path
from typing import Optional

from strands.telemetry import StrandsTelemetry


class Config:
    """Centralized configuration management."""

    _telemetry_instance: Optional[StrandsTelemetry] = None

    @staticmethod
    def setup_logging(
        log_level: str = "INFO",
        log_file: Optional[str] = None,
        include_console: bool = True,
    ) -> None:
        """Setup centralized logging configuration."""
        handlers = []

        if log_file:
            log_dir = Path(os.getenv("AIOPS_LOG_DIR", str(Path.home() / ".aiops")))
            log_path = log_dir / log_file
            log_path.parent.mkdir(parents=True, exist_ok=True)
            handlers.append(logging.FileHandler(log_path))

        if include_console:
            handlers.append(logging.StreamHandler())

        logging.basicConfig(
            level=getattr(logging, log_level.upper()),
            format="%(asctime)s | %(levelname)s | %(name)s | %(message)s",
            handlers=handlers,
            force=True,
        )

        logging.getLogger("strands").setLevel(getattr(logging, log_level.upper()))

        if log_file:
            logger = logging.getLogger(__name__)
            logger.info(f"Logging configured - File: {log_path}, Level: {log_level}")

    @staticmethod
    def _setup_langfuse() -> None:
        """Setup Langfuse OTLP configuration (optional)."""
        public_key = os.getenv("LANGFUSE_PUBLIC_KEY")
        secret_key = os.getenv("LANGFUSE_SECRET_KEY")
        langfuse_host = os.getenv(
            "LANGFUSE_HOST", "https://us.cloud.langfuse.com"
        )

        if not public_key or not secret_key:
            return

        langfuse_auth = base64.b64encode(
            f"{public_key}:{secret_key}".encode()
        ).decode()

        os.environ["OTEL_EXPORTER_OTLP_ENDPOINT"] = (
            f"{langfuse_host}/api/public/otel"
        )
        os.environ["OTEL_EXPORTER_OTLP_HEADERS"] = (
            f"Authorization=Basic {langfuse_auth}"
        )

        logger = logging.getLogger(__name__)
        logger.info(f"Langfuse OTLP configured - Endpoint: {langfuse_host}/api/public/otel")

    @staticmethod
    def setup_telemetry(
        enable_otlp: bool = False,
        enable_console: bool = False,
        enable_langfuse: bool = False,
    ) -> None:
        """Setup centralized telemetry configuration."""
        if not enable_otlp and not enable_console and not enable_langfuse:
            return

        if enable_langfuse:
            Config._setup_langfuse()

        if Config._telemetry_instance is None:
            Config._telemetry_instance = StrandsTelemetry()
            if not enable_langfuse:
                os.environ.setdefault(
                    "OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4318"
                )

        if enable_otlp or enable_langfuse:
            Config._telemetry_instance.setup_otlp_exporter()

        if enable_console:
            Config._telemetry_instance.setup_console_exporter()

    @staticmethod
    def setup_environment() -> None:
        """Setup common environment variables.

        Daemon-related env vars (see daemon.py):
            AIOPS_DAEMON_ENABLED: "true" to auto-start daemon (default: true)
            AIOPS_HEALTH_CHECK_INTERVAL: seconds between checks (default: 900 = 15 min)
            AIOPS_DAEMON_MODEL: Bedrock model ID for daemon (default: amazon.nova-pro-v1:0)
        """
        os.environ.setdefault("BYPASS_TOOL_CONSENT", "true")
        kubeconfig = os.getenv("KUBECONFIG", os.path.expanduser("~/.kube/config"))
        os.environ["KUBECONFIG"] = kubeconfig

    @staticmethod
    def setup_for_mcp() -> None:
        """Setup configuration for MCP server execution."""
        Config.setup_logging(
            log_level="INFO",
            log_file="aiops-mcp.log",
            include_console=True,
        )

        enable_langfuse = bool(
            os.getenv("LANGFUSE_PUBLIC_KEY") and os.getenv("LANGFUSE_SECRET_KEY")
        )
        Config.setup_telemetry(
            enable_otlp=True, enable_console=True, enable_langfuse=enable_langfuse
        )
        Config.setup_environment()

    @staticmethod
    def setup_for_development() -> None:
        """Setup configuration for local development."""
        log_level = os.getenv("LOG_LEVEL", "INFO")
        Config.setup_logging(log_level=log_level, include_console=True)

        enable_langfuse = bool(
            os.getenv("LANGFUSE_PUBLIC_KEY") and os.getenv("LANGFUSE_SECRET_KEY")
        )
        # Only enable OTLP if an exporter endpoint is explicitly set or Langfuse is configured
        enable_otlp = bool(os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT")) or enable_langfuse
        Config.setup_telemetry(
            enable_otlp=enable_otlp, enable_console=False, enable_langfuse=enable_langfuse
        )
        Config.setup_environment()
