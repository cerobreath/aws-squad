"""Cluster profile auto-discovery with in-memory TTL cache."""
import logging
import os
import threading
import time

logger = logging.getLogger(__name__)

DEFAULT_TTL_SECONDS = 3600  # 1 hour


class ClusterProfile:
    """In-memory cache for cluster topology profiles."""

    _cache: dict = {}
    _lock = threading.Lock()

    def __init__(self):
        self._ttl_seconds = int(
            os.getenv("AIOPS_PROFILE_TTL_SECONDS", str(DEFAULT_TTL_SECONDS))
        )

    def get_profile(self, cluster_name: str) -> str | None:
        """Return cached profile string if it exists and hasn't expired."""
        with self._lock:
            entry = self._cache.get(cluster_name)
            if entry is None:
                return None
            if time.time() > entry["expires_at"]:
                logger.info(f"Cached profile for '{cluster_name}' has expired")
                del self._cache[cluster_name]
                return None
            logger.info(f"Cache hit for cluster '{cluster_name}'")
            return entry["data"]

    def save_profile(self, cluster_name: str, profile_data: str) -> None:
        """Store a cluster profile with TTL."""
        with self._lock:
            self._cache[cluster_name] = {
                "data": profile_data,
                "expires_at": time.time() + self._ttl_seconds,
            }
        logger.info(
            f"Saved profile for '{cluster_name}' (TTL {self._ttl_seconds}s)"
        )
