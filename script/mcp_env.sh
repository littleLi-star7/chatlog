#!/usr/bin/env bash
set -euo pipefail

# Configure environment for Chatlog MCP (Streamable HTTP) running on Windows host.
# Usage:
#   # Preview endpoints
#   bash script/mcp_env.sh
#   # Export env into current shell
#   eval "$(bash script/mcp_env.sh export)"

repo_root() { cd "$(dirname "$0")/.." && pwd; }

host_ip() {
  bash "$(repo_root)/script/host_ip.sh"
}

main() {
  local ip
  ip=$(host_ip)
  local base="http://${ip}:5030"
  local mcp="${base}/mcp"

  if [ "${1:-}" = "export" ]; then
    cat <<EOF
export MCP_CHATLOG_HOST_IP=${ip}
export MCP_CHATLOG_BASE=${base}
export MCP_CHATLOG_MCP=${mcp}
EOF
    exit 0
  fi

  echo "Detected host IP: ${ip}"
  echo "MCP base: ${base}"
  echo "MCP endpoint: ${mcp}"

  # Optional quick checks
  if command -v curl >/dev/null 2>&1; then
    echo "- Checking health: ${base}/health"
    set +e
    http_code=$(curl -sS -o /dev/null -w "%{http_code}" "${base}/health")
    set -e
    echo "  HTTP ${http_code:-N/A}"
  fi
}

main "$@"

