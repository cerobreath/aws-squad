FROM python:3.12-slim

# Install uv (used by uvx to run MCP servers as subprocesses)
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

# Install AWS CLI v2 and kubectl (needed for EKS auth + kubectl-mcp-server)
RUN apt-get update && apt-get install -y --no-install-recommends curl unzip && \
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip && \
    unzip -q /tmp/awscliv2.zip -d /tmp && /tmp/aws/install && \
    rm -rf /tmp/awscliv2.zip /tmp/aws && \
    curl -fsSLO "https://dl.k8s.io/release/v1.33.0/bin/linux/amd64/kubectl" && \
    install kubectl /usr/local/bin/kubectl && rm kubectl && \
    apt-get purge -y unzip && apt-get autoremove -y && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Fix kubectl-mcp-server bug: MCPServer.__init__() doesn't accept non_destructive kwarg
RUN MAIN_PY=$(python -c "import kubectl_mcp_tool, os; print(os.path.join(os.path.dirname(kubectl_mcp_tool.__file__), '__main__.py'))") && \
    sed -i 's/MCPServer(name="kubernetes", non_destructive=args.non_destructive)/MCPServer(name="kubernetes")/' "$MAIN_PY"

# Pre-install mcp-grafana so first request doesn't pay the download cost
RUN uvx mcp-grafana --help > /dev/null 2>&1 || true

# Copy application code into aiops package directory
COPY . ./aiops/

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')"

ENTRYPOINT ["/entrypoint.sh"]
