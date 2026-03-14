FROM python:3.12-slim

# Install uv (used by uvx to run MCP servers as subprocesses)
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

WORKDIR /app

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Pre-install MCP servers so first request doesn't pay the download cost
RUN uvx kubectl-mcp-server --help > /dev/null 2>&1 || true && \
    uvx mcp-grafana --help > /dev/null 2>&1 || true

# Copy application code
COPY . .

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')"

CMD ["uvicorn", "aiops.web:app", "--host", "0.0.0.0", "--port", "8000"]
