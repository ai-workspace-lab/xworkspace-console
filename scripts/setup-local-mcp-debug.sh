#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${XWORKSPACE_MCP_OUT_DIR:-$ROOT_DIR/config/mcp}"
BIN_DIR="${OUT_DIR}/bin"
ENV_FILE="${OUT_DIR}/local-mcp.env"
PROFILE_FILE="${OUT_DIR}/local-mcp-config.json"

mkdir -p "$OUT_DIR" "$BIN_DIR"

have() { command -v "$1" >/dev/null 2>&1; }

need_cmd() {
  local cmd="$1"
  if ! have "$cmd"; then
    printf '[ERROR] missing required command: %s\n' "$cmd" >&2
    exit 1
  fi
}

need_cmd docker

if [ -n "${GITHUB_PERSONAL_ACCESS_TOKEN:-}" ]; then
  umask 077
  cat >"$ENV_FILE" <<EOF
GITHUB_PERSONAL_ACCESS_TOKEN=${GITHUB_PERSONAL_ACCESS_TOKEN}
EOF
elif [ ! -f "$ENV_FILE" ]; then
  cat <<EOF >&2
[ERROR] GITHUB_PERSONAL_ACCESS_TOKEN is required.
Set it in your shell once, or create:
  ${ENV_FILE}
EOF
  exit 1
fi

cat >"${BIN_DIR}/github-mcp-server.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "${ROOT_DIR}/config/mcp/local-mcp.env"
exec docker run --rm -i \
  -e GITHUB_PERSONAL_ACCESS_TOKEN \
  -e GITHUB_TOOLSETS=default,actions \
  ghcr.io/github/github-mcp-server:latest
EOF

cat >"${BIN_DIR}/terraform-mcp-server.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exec docker run --rm -i \
  ghcr.io/hashicorp/terraform-mcp-server:latest \
  --toolsets=registry
EOF

cat >"${BIN_DIR}/mcp-ssh-manager.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exec npx -y mcp-ssh-manager@latest
EOF

chmod +x "${BIN_DIR}/github-mcp-server.sh" "${BIN_DIR}/terraform-mcp-server.sh" "${BIN_DIR}/mcp-ssh-manager.sh"

if ! have ansible-galaxy; then
  printf '[WARN] ansible-galaxy not found; skipping ansible.mcp collection install.\n' >&2
else
  printf '[INFO] installing ansible.mcp collection...\n' >&2
  ansible-galaxy collection install ansible.mcp ansible.utils >/dev/null
fi

cat >"$PROFILE_FILE" <<JSON
{
  "mcpServers": {
    "github": {
      "command": "${BIN_DIR}/github-mcp-server.sh"
    },
    "terraform": {
      "command": "${BIN_DIR}/terraform-mcp-server.sh"
    },
    "ssh-manager": {
      "command": "${BIN_DIR}/mcp-ssh-manager.sh"
    }
  }
}
JSON

cat <<EOF
[SUCCESS] wrote ${ENV_FILE}
[SUCCESS] wrote ${PROFILE_FILE}

Point your MCP client at:
  ${PROFILE_FILE}

Notes:
- The GitHub wrapper loads the token from ${ENV_FILE}, so you only need to run this once.
- Terraform MCP stays on the minimal registry toolset.
- SSH Manager runs through npx to avoid a global install.
- ansible.mcp is a collection dependency, not a standalone MCP daemon.
EOF
