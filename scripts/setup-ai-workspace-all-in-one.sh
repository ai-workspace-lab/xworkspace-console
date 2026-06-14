#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# AI Workspace All-in-One Bootstrap Script
# ==============================================================================
# Usage:
#   curl -sfL https://raw.githubusercontent.com/ai-workspace-infra/playbooks/main/setup-ai-workspace-all-in-one.sh | bash -
#
# Supported Environment Variables:
#   AI_WORKSPACE_SECURITY_LEVEL
#   LITELLM_API_CADDY_STRICT_WHITELIST
#   XWORKSPACE_CONSOLE_PUBLIC_ACCESS
#   XWORKMATE_BRIDGE_PUBLIC_ACCESS
#   GATEWAY_OPENCLAW_PUBLIC_ACCESS
#   VAULT_PUBLIC_ACCESS
#   XWORKSPACE_CONSOLE_ENABLE_XRDP
#   AI_WORKSPACE_AUTH_TOKEN / XWORKSPACE_CONSOLE_AUTH_TOKEN
#     / XWORKMATE_BRIDGE_AUTH_TOKEN / BRIDGE_AUTH_TOKEN / INTERNAL_SERVICE_TOKEN
#     / DEPLOY_TOKEN
#       Unified auth token passed to xworkmate-bridge, LiteLLM, OpenClaw, and Vault.
#   PLAYBOOK_DIR (optional local playbooks checkout; useful for macOS validation)
#   XWORKSPACE_CONSOLE_DIR (optional local xworkspace-console checkout for macOS)
#   AI_WORKSPACE_DARWIN_MODE=local (default on macOS) | ansible
# ==============================================================================

REPO_URL=${REPO_URL:-"https://github.com/ai-workspace-infra/playbooks.git"}
BRANCH=${BRANCH:-"main"}
TARGET_DIR=${TARGET_DIR:-"/tmp/ai-workspace-deploy"}
PLAYBOOK_DIR=${PLAYBOOK_DIR:-""}
XWORKSPACE_CONSOLE_REPO_URL=${XWORKSPACE_CONSOLE_REPO_URL:-"https://github.com/ai-workspace-lab/xworkspace-console.git"}
XWORKSPACE_CONSOLE_DIR=${XWORKSPACE_CONSOLE_DIR:-""}
AUTH_TOKEN_FILE=${AI_WORKSPACE_AUTH_TOKEN_FILE:-"$HOME/.ai_workspace_auth_token"}
VAULT_FILE=${AI_WORKSPACE_VAULT_PASSWORD_FILE:-"$HOME/.vault_password"}

# Function: Output messages
info() {
    echo -e "\033[1;34m[INFO]\033[0m $*" >&2
}
success() {
    echo -e "\033[1;32m[SUCCESS]\033[0m $*" >&2
}
error() {
    echo -e "\033[1;31m[ERROR]\033[0m $*" >&2
    exit 1
}

mask_secret() {
    local val="${1:-}"
    if [ -z "$val" ]; then
        echo "<empty>"
    elif [ "${#val}" -le 8 ]; then
        echo "<hidden>"
    else
        echo "${val:0:4}...${val: -4}"
    fi
}

detect_os() {
    case "$(uname -s)" in
        Darwin) echo "darwin" ;;
        Linux) echo "linux" ;;
        *) echo "unknown" ;;
    esac
}

install_prerequisites() {
    local os="$1"
    info "Installing required dependencies (git, ansible)..."
    if [ "$os" = "linux" ]; then
        if [ -f /etc/debian_version ]; then
            sudo apt-get update -y
            if grep -qi ubuntu /etc/os-release 2>/dev/null; then
                sudo DEBIAN_FRONTEND=noninteractive apt-get install -y git curl software-properties-common
                sudo apt-add-repository --yes --update ppa:ansible/ansible
                sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ansible
            else
                sudo DEBIAN_FRONTEND=noninteractive apt-get install -y git curl ansible
            fi
        elif [ -f /etc/redhat-release ]; then
            sudo yum install -y epel-release
            sudo yum install -y git curl ansible
        else
            error "Unsupported Linux distribution. Please install git and ansible manually."
        fi
    elif [ "$os" = "darwin" ]; then
        if command -v brew >/dev/null 2>&1; then
            brew install git ansible
        else
            error "macOS requires git and ansible. Install Homebrew or install them manually, then rerun."
        fi
    else
        error "Unsupported OS. Please install git and ansible manually."
    fi
    success "Dependencies installed."
}

resolve_unified_auth_token() {
    local token="${AI_WORKSPACE_AUTH_TOKEN:-}"
    if [ -z "$token" ]; then token="${XWORKSPACE_CONSOLE_AUTH_TOKEN:-}"; fi
    if [ -z "$token" ]; then token="${XWORKMATE_BRIDGE_AUTH_TOKEN:-}"; fi
    if [ -z "$token" ]; then token="${BRIDGE_AUTH_TOKEN:-}"; fi
    if [ -z "$token" ]; then token="${INTERNAL_SERVICE_TOKEN:-}"; fi
    if [ -z "$token" ]; then token="${DEPLOY_TOKEN:-}"; fi

    if [ -n "$token" ]; then
        printf '%s' "$token" > "$AUTH_TOKEN_FILE"
        chmod 600 "$AUTH_TOKEN_FILE"
        info "Using provided unified auth token: $(mask_secret "$token")"
        printf '%s' "$token"
        return
    fi

    if [ -f "$AUTH_TOKEN_FILE" ]; then
        info "Found existing unified auth token at $AUTH_TOKEN_FILE, reusing it."
        tr -d '\r\n' < "$AUTH_TOKEN_FILE"
        return
    fi

    info "No unified auth token provided. Generating a secure random token..."
    openssl rand -base64 32 | tr -d '\r\n' > "$AUTH_TOKEN_FILE"
    chmod 600 "$AUTH_TOKEN_FILE"
    info "Generated new unified auth token and saved to $AUTH_TOKEN_FILE"
    cat "$AUTH_TOKEN_FILE"
}

require_or_install_macos_cmds() {
    local missing=()
    for cmd in git node npm go curl lsof python3; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done
    if [ "${#missing[@]}" -eq 0 ]; then
        return
    fi
    if ! command -v brew >/dev/null 2>&1; then
        error "Missing required commands on macOS: ${missing[*]}. Install Homebrew or install them manually."
    fi
    info "Installing missing macOS dependencies: ${missing[*]}"
    for cmd in "${missing[@]}"; do
        case "$cmd" in
            git) brew install git ;;
            node|npm) brew install node ;;
            go) brew install go ;;
            python3) brew install python@3.13 ;;
            curl) brew install curl ;;
            lsof) error "lsof is part of macOS; it is missing from PATH." ;;
        esac
    done
}

macos_litellm_python() {
    for py in python3.13 python3.12 python3.11; do
        if command -v "$py" >/dev/null 2>&1; then
            command -v "$py"
            return
        fi
    done
    if command -v brew >/dev/null 2>&1; then
        info "Installing python@3.13 for LiteLLM compatibility..."
        brew install python@3.13
        command -v python3.13
        return
    fi
    error "LiteLLM requires Python 3.11-3.13 on macOS. Install python3.13 or Homebrew."
}

macos_openclaw_bin() {
    if command -v openclaw >/dev/null 2>&1; then
        command -v openclaw
        return
    fi
    local prefix="$HOME/.local/share/xworkspace/node"
    info "Installing OpenClaw CLI locally under $prefix..."
    mkdir -p "$prefix"
    npm install --prefix "$prefix" openclaw@2026.6.1 @openclaw/codex@2026.6.1
    printf '%s/bin/openclaw\n' "$prefix"
}

macos_vault_bin() {
    if command -v vault >/dev/null 2>&1; then
        command -v vault
        return
    fi
    if command -v brew >/dev/null 2>&1; then
        info "Installing Vault CLI/server with Homebrew..."
        brew install hashicorp/tap/vault || brew install vault
        command -v vault
        return
    fi
    error "Vault is required for local macOS deployment. Install vault or Homebrew."
}

macos_ttyd_bin() {
    if command -v ttyd >/dev/null 2>&1; then
        command -v ttyd
        return
    fi
    if command -v brew >/dev/null 2>&1; then
        info "Installing ttyd with Homebrew..."
        brew install ttyd
        command -v ttyd
        return
    fi
    error "ttyd is required for the local Portal terminal. Install ttyd or Homebrew."
}

macos_postgres_tool() {
    local tool=$1
    if command -v "$tool" >/dev/null 2>&1; then
        command -v "$tool"
        return
    fi
    for base in /opt/homebrew/opt/postgresql@16/bin /usr/local/opt/postgresql@16/bin /opt/homebrew/opt/postgresql@15/bin /usr/local/opt/postgresql@15/bin /opt/homebrew/opt/postgresql@14/bin /usr/local/opt/postgresql@14/bin /opt/homebrew/bin /usr/local/bin; do
        if [ -x "$base/$tool" ]; then
            printf '%s/%s\n' "$base" "$tool"
            return
        fi
    done
    if command -v brew >/dev/null 2>&1; then
        info "Installing PostgreSQL for LiteLLM local UI storage..."
        brew install postgresql@16 || brew install postgresql
        if command -v "$tool" >/dev/null 2>&1; then
            command -v "$tool"
            return
        fi
        for base in /opt/homebrew/opt/postgresql@16/bin /usr/local/opt/postgresql@16/bin /opt/homebrew/opt/postgresql/bin /usr/local/opt/postgresql/bin; do
            if [ -x "$base/$tool" ]; then
                printf '%s/%s\n' "$base" "$tool"
                return
            fi
        done
    fi
    error "PostgreSQL tool '$tool' is required for local LiteLLM UI login."
}

resolve_console_dir() {
    if [ -n "$XWORKSPACE_CONSOLE_DIR" ]; then
        [ -d "$XWORKSPACE_CONSOLE_DIR/dashboard" ] && [ -d "$XWORKSPACE_CONSOLE_DIR/api" ] || \
            error "XWORKSPACE_CONSOLE_DIR must contain dashboard/ and api/: $XWORKSPACE_CONSOLE_DIR"
        cd "$XWORKSPACE_CONSOLE_DIR"
        pwd
        return
    fi

    local script_dir=""
    if [ -n "${BASH_SOURCE[0]:-}" ]; then
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P || true)"
    fi
    if [ -n "$script_dir" ] && [ -d "$script_dir/../dashboard" ] && [ -d "$script_dir/../api" ]; then
        cd "$script_dir/.."
        pwd
        return
    fi
    if [ -d "$PWD/dashboard" ] && [ -d "$PWD/api" ]; then
        pwd
        return
    fi

    local checkout_dir="${XWORKSPACE_CONSOLE_CHECKOUT_DIR:-$HOME/xworkspace-console}"
    if [ -d "$checkout_dir/.git" ]; then
        info "Updating xworkspace-console checkout at $checkout_dir..."
        git -C "$checkout_dir" fetch origin
        git -C "$checkout_dir" reset --hard origin/main
    else
        info "Cloning xworkspace-console to $checkout_dir..."
        git clone "$XWORKSPACE_CONSOLE_REPO_URL" "$checkout_dir"
    fi
    cd "$checkout_dir"
    pwd
}

write_litellm_config() {
    local config_file=$1
    mkdir -p "$(dirname "$config_file")"
    cat > "$config_file" <<'YAML'
model_list: []

general_settings:
  master_key: "os.environ/LITELLM_MASTER_KEY"
  database_url: "os.environ/DATABASE_URL"
  store_model_in_db: true
  drop_rate_limit_requests: true

router_settings:
  routing_strategy: simple-shuffle
  num_retries: 2
  retry_after: 30
  fallbacks: []

litellm_settings:
  drop_params: true
  set_verbose: false
  request_timeout: 600
  telemetry: false
YAML
}

ensure_secret_file() {
    local file=$1
    mkdir -p "$(dirname "$file")"
    if [ -s "$file" ]; then
        tr -d '\r\n' < "$file"
        return
    fi
    openssl rand -hex 20 > "$file"
    chmod 600 "$file"
    cat "$file"
}

ensure_litellm_venv() {
    local venv_dir=$1
    local py_bin=$2
    if [ ! -x "$venv_dir/bin/litellm" ]; then
        info "Creating LiteLLM virtualenv at $venv_dir..."
        rm -rf "$venv_dir"
        "$py_bin" -m venv "$venv_dir"
        "$venv_dir/bin/python" -m pip install --upgrade pip
        "$venv_dir/bin/python" -m pip install 'litellm[proxy,extra-proxy]'
        return
    fi
    if ! "$venv_dir/bin/python" -c 'import prisma' >/dev/null 2>&1; then
        info "Adding LiteLLM database dependencies to existing virtualenv..."
        "$venv_dir/bin/python" -m pip install 'litellm[extra-proxy]'
    fi
}

ensure_litellm_prisma_client() {
    local venv_dir=$1
    local database_url=$2
    local schema_file
    schema_file="$("$venv_dir/bin/python" - <<'PY'
import importlib.util
import pathlib

spec = importlib.util.find_spec("litellm.proxy")
if spec is None or spec.origin is None:
    raise SystemExit("Unable to locate litellm.proxy schema")
print(pathlib.Path(spec.origin).with_name("schema.prisma"))
PY
)"
    info "Syncing LiteLLM Prisma client and database schema..."
    PATH="$venv_dir/bin:$PATH" DATABASE_URL="$database_url" "$venv_dir/bin/prisma" db push --schema "$schema_file"
}

write_local_portal_config() {
    local token=$1
    local config_dir=$2
    mkdir -p "$config_dir"
    cat > "$config_dir/portal-services.json" <<'JSON'
{
  "services": [
    {
      "key": "litellm",
      "name": "LiteLLM Admin UI",
      "url": "http://localhost:4000/ui",
      "openMode": "iframe",
      "healthUrl": "http://127.0.0.1:4000/ui",
      "description": "Model routing and provider administration.",
      "icon": "chart",
      "match": ["litellm", "lite"],
      "port": 4000,
      "role": "model-router"
    },
    {
      "key": "openclaw",
      "name": "OpenClaw",
      "url": "http://127.0.0.1:18789/channels",
      "openMode": "external",
      "healthUrl": "http://127.0.0.1:18789/channels",
      "description": "Gateway dashboard.",
      "icon": "claw",
      "match": ["openclaw", "gateway"],
      "port": 18789,
      "role": "gateway"
    },
    {
      "key": "vault",
      "name": "Vault Server",
      "url": "http://127.0.0.1:8200/ui",
      "openMode": "external",
      "healthUrl": "http://127.0.0.1:8200/ui",
      "description": "Vault UI.",
      "icon": "shield",
      "match": ["vault"],
      "port": 8200
    },
    {
      "key": "terminal",
      "name": "Terminal",
      "url": "http://127.0.0.1:7681",
      "openMode": "iframe",
      "healthUrl": "http://127.0.0.1:7681",
      "description": "Local ttyd terminal.",
      "icon": "terminal",
      "match": ["ttyd", "terminal"],
      "port": 7681
    }
  ]
}
JSON
    printf '%s\n' "$token" > "$config_dir/auth-token"
    chmod 600 "$config_dir/auth-token"
    printf '%s\n' "$token" > "$AUTH_TOKEN_FILE"
    chmod 600 "$AUTH_TOKEN_FILE"
    cat > "$config_dir/portal.env" <<EOF
AI_WORKSPACE_AUTH_TOKEN=$token
XWORKSPACE_CONSOLE_AUTH_TOKEN=$token
BRIDGE_AUTH_TOKEN=$token
XWORKMATE_BRIDGE_AUTH_TOKEN=$token
INTERNAL_SERVICE_TOKEN=$token
LITELLM_MASTER_KEY=$token
OPENCLAW_GATEWAY_TOKEN=$token
VAULT_TOKEN=$token
VAULT_SERVER_ROOT_ACCESS_TOKEN=$token
VAULT_ADMIN_PASSWORD=$token
XWORKSPACE_PORTAL_SERVICES_FILE=$config_dir/portal-services.json
EOF
    chmod 600 "$config_dir/portal.env"
}

stop_managed_pid() {
    local pid_file=$1
    if [ ! -f "$pid_file" ]; then
        return
    fi
    local pid
    pid="$(cat "$pid_file" 2>/dev/null || true)"
    if [ -n "$pid" ] && kill -0 "$pid" >/dev/null 2>&1; then
        info "Stopping previous managed process $pid..."
        kill "$pid" >/dev/null 2>&1 || true
        sleep 1
    fi
    rm -f "$pid_file"
}

ensure_port_available_for_repo() {
    local port=$1
    local repo_dir=$2
    local pid
    pid="$(lsof -nP -tiTCP:"$port" -sTCP:LISTEN | head -n 1 || true)"
    if [ -z "$pid" ]; then
        return
    fi
    local cwd
    cwd="$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -n 1 || true)"
    if [ -n "$cwd" ] && [[ "$cwd" == "$repo_dir"* ]]; then
        info "Port $port is already used by this checkout (pid $pid); restarting it."
        kill "$pid" >/dev/null 2>&1 || true
        sleep 1
        return
    fi
    error "Port $port is already in use by pid $pid ($cwd). Stop it or choose a clean local session."
}

ensure_port_available() {
    local port=$1
    local pid
    pid="$(lsof -nP -tiTCP:"$port" -sTCP:LISTEN | head -n 1 || true)"
    if [ -z "$pid" ]; then
        return
    fi
    local command_name
    command_name="$(ps -p "$pid" -o comm= 2>/dev/null || true)"
    error "Port $port is already in use by pid $pid ($command_name). Stop it or choose another port."
}

patch_playbook_user_systemd() {
    local playbook="setup-xworkspace-console.yaml"
    if [ ! -f "$playbook" ]; then
        return
    fi
    python3 - <<'PY'
from pathlib import Path

path = Path("setup-xworkspace-console.yaml")
text = path.read_text()

commands = {
    'su - {{ xworkspace_console_user }} -c "systemctl --user daemon-reload"': 'systemctl --user daemon-reload',
    'su - {{ xworkspace_console_user }} -c "systemctl --user restart xworkspace-console.service"': 'systemctl --user restart xworkspace-console.service',
    'su - {{ xworkspace_console_user }} -c "systemctl --user restart xworkspace-ttyd.service"': 'systemctl --user restart xworkspace-ttyd.service',
}

def wrapped(systemctl_command: str) -> str:
    lines = [
        'uid="$(id -u {{ xworkspace_console_user }})"',
        'loginctl enable-linger {{ xworkspace_console_user }} || true',
        'systemctl start "user@${uid}.service" || true',
        f'runuser -u {{{{ xworkspace_console_user }}}} -- env XDG_RUNTIME_DIR="/run/user/${{uid}}" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${{uid}}/bus" {systemctl_command}',
    ]
    return "\n        ".join(lines)

updated = text
for old, command in commands.items():
    updated = updated.replace(old, wrapped(command))

if updated != text:
    path.write_text(updated)
PY
}

wait_for_url() {
    local url=$1
    local header=${2:-}
    local attempts=120
    local status
    for _ in $(seq 1 "$attempts"); do
        if [ -n "$header" ]; then
            status="$(curl -sS -o /dev/null -w '%{http_code}' -H "$header" "$url" 2>/dev/null || true)"
        else
            status="$(curl -sS -o /dev/null -w '%{http_code}' "$url" 2>/dev/null || true)"
        fi
        case "$status" in
            2*|3*|401) return 0 ;;
        esac
        sleep 0.5
    done
    error "Timed out waiting for $url"
}

wait_for_postgres() {
    local pg_isready_bin=$1
    local socket_dir=$2
    local port=$3
    local attempts=60
    for _ in $(seq 1 "$attempts"); do
        if "$pg_isready_bin" -h "$socket_dir" -p "$port" >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.5
    done
    error "Timed out waiting for local PostgreSQL on port $port"
}

service_status_line() {
    local label=$1
    local unit_patterns=$2
    local port=${3:-}
    local detail="not detected"
    local state="DOWN"

    if command -v systemctl >/dev/null 2>&1; then
        local unit
        for unit in $unit_patterns; do
            if systemctl is-active --quiet "$unit" 2>/dev/null; then
                state="OK"
                detail="systemd:$unit"
                break
            fi
        done
    fi

    if [ "$state" != "OK" ] && [ -n "$port" ]; then
        if command -v ss >/dev/null 2>&1 && ss -ltn "( sport = :$port )" 2>/dev/null | grep -q ":$port"; then
            state="OK"
            detail="port:$port"
        elif command -v lsof >/dev/null 2>&1 && lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
            state="OK"
            detail="port:$port"
        fi
    fi

    printf '  - %-28s %s (%s)\n' "$label" "$state" "$detail"
}

cli_status_line() {
    local label=$1
    local bin=$2
    local state="MISSING"
    local detail="not in PATH"

    if command -v "$bin" >/dev/null 2>&1; then
        state="OK"
        detail="$(command -v "$bin")"
    fi

    printf '  - %-28s %s (%s)\n' "$label" "$state" "$detail"
}

print_deployment_summary() {
    local domain=${SERVER_DOMAIN:-${XWORKMATE_BRIDGE_DOMAIN:-${BRIDGE_DOMAIN:-${ACP_BRIDGE_DOMAIN:-acp-bridge.onwalk.net}}}}
    local token=$1

    cat <<EOF

AI Workspace Deployment Summary
Domain: ${domain}
Token: ${token}

AI workspace (runtime desktop/browser):
EOF
    service_status_line "Runtime desktop/browser" "xworkspace-shell.service xworkspace-console.service display-manager.service gdm.service lightdm.service" "17000"
    service_status_line "Workspace portal (console)" "xworkspace-console.service xworkspace-api.service" "17000"
    service_status_line "OpenClaw" "xworkspace-openclaw.service openclaw-gateway.service openclaw.service" "18789"
    service_status_line "QMD" "xworkspace-qmd.service qmd.service qdrant.service" "6333"
    service_status_line "Hermes" "xworkspace-hermes.service hermes.service" ""
    service_status_line "PG" "postgresql.service postgresql@16-main.service postgresql@15-main.service xworkspace-postgres.service" "5432"
    service_status_line "Vault" "xworkspace-vault.service vault.service" "8200"
    service_status_line "LiteLLM" "xworkspace-litellm.service litellm-proxy.service litellm.service" "4000"

    cat <<'EOF'

Agent CLI:
EOF
    cli_status_line "opencode" "opencode"
    cli_status_line "gemini" "gemini"
    cli_status_line "codex" "codex"
    cli_status_line "claude" "claude"
    printf '\n'
}

deploy_launch_agent() {
    local label=$1
    local workdir=$2
    local command=$3
    local stdout_log=$4
    local stderr_log=$5
    local plist_dir="$HOME/Library/LaunchAgents"
    local plist="$plist_dir/$label.plist"
    local domain="gui/$(id -u)"

    mkdir -p "$plist_dir" "$(dirname "$stdout_log")" "$(dirname "$stderr_log")"
    cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$label</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>-lc</string>
    <string>$command</string>
  </array>
  <key>WorkingDirectory</key>
  <string>$workdir</string>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$stdout_log</string>
  <key>StandardErrorPath</key>
  <string>$stderr_log</string>
</dict>
</plist>
EOF

    launchctl bootout "$domain" "$plist" >/dev/null 2>&1 || true
    launchctl bootstrap "$domain" "$plist" >/dev/null
    launchctl kickstart -k "$domain/$label" >/dev/null
}

ensure_macos_litellm_database() {
    local config_dir=$1
    local state_dir=$2
    local tool_path=$3
    local pg_port="${AI_WORKSPACE_LITELLM_POSTGRES_PORT:-15432}"
    local pg_data="$HOME/.local/share/xworkspace/postgres-data"
    local pg_socket_dir="$state_dir/postgres-socket"
    local db_name="litellm"
    local db_user="litellm"
    local db_password_file="$config_dir/litellm-db-password"
    local db_password postgres_bin initdb_bin psql_bin pg_isready_bin

    db_password="$(ensure_secret_file "$db_password_file")"
    postgres_bin="$(macos_postgres_tool postgres)"
    initdb_bin="$(macos_postgres_tool initdb)"
    psql_bin="$(macos_postgres_tool psql)"
    pg_isready_bin="$(macos_postgres_tool pg_isready)"

    mkdir -p "$pg_data" "$pg_socket_dir"
    chmod 700 "$pg_socket_dir"
    if [ ! -f "$pg_data/PG_VERSION" ]; then
        info "Initializing local PostgreSQL data directory at $pg_data ..."
        "$initdb_bin" -D "$pg_data" --auth-local=trust --auth-host=scram-sha-256 >/dev/null
    fi

    launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/plus.svc.xworkspace.postgres.plist" >/dev/null 2>&1 || true
    sleep 1
    ensure_port_available "$pg_port"

    info "Starting local PostgreSQL for LiteLLM on 127.0.0.1:$pg_port ..."
    deploy_launch_agent \
        "plus.svc.xworkspace.postgres" \
        "$HOME" \
        "exec /usr/bin/env PATH='$tool_path' '$postgres_bin' -D '$pg_data' -h 127.0.0.1 -p '$pg_port' -k '$pg_socket_dir'" \
        "$state_dir/postgres.log" \
        "$state_dir/postgres.err.log"
    wait_for_postgres "$pg_isready_bin" "$pg_socket_dir" "$pg_port"

    "$psql_bin" -h "$pg_socket_dir" -p "$pg_port" -d postgres -v ON_ERROR_STOP=1 >/dev/null <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$db_user') THEN
    CREATE ROLE "$db_user" LOGIN PASSWORD '$db_password';
  ELSE
    ALTER ROLE "$db_user" LOGIN PASSWORD '$db_password';
  END IF;
END
\$\$;
SELECT format('CREATE DATABASE %I OWNER %I', '$db_name', '$db_user')
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = '$db_name') \gexec
ALTER DATABASE "$db_name" OWNER TO "$db_user";
SQL

    PGPASSWORD="$db_password" "$psql_bin" -h 127.0.0.1 -p "$pg_port" -U "$db_user" -d "$db_name" -v ON_ERROR_STOP=1 -Atc 'select 1' >/dev/null
    printf 'postgresql://%s:%s@127.0.0.1:%s/%s?sslmode=disable\n' "$db_user" "$db_password" "$pg_port" "$db_name"
}

start_macos_target_services() {
    local config_dir=$1
    local state_dir=$2
    local tool_path=$3
    local litellm_py litellm_venv litellm_config litellm_bin openclaw_bin vault_bin ttyd_bin litellm_database_url

    chmod 700 "$state_dir"
    litellm_py="$(macos_litellm_python)"
    litellm_venv="$HOME/.local/share/xworkspace/litellm-venv"
    litellm_config="$config_dir/litellm-config.yaml"
    ensure_litellm_venv "$litellm_venv" "$litellm_py"
    litellm_database_url="$(ensure_macos_litellm_database "$config_dir" "$state_dir" "$tool_path")"
    ensure_litellm_prisma_client "$litellm_venv" "$litellm_database_url"
    write_litellm_config "$litellm_config"
    litellm_bin="$litellm_venv/bin/litellm"
    openclaw_bin="$(macos_openclaw_bin)"
    vault_bin="$(macos_vault_bin)"
    ttyd_bin="$(macos_ttyd_bin)"

    launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/plus.svc.xworkspace.litellm.plist" >/dev/null 2>&1 || true
    launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/plus.svc.xworkspace.openclaw.plist" >/dev/null 2>&1 || true
    launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/plus.svc.xworkspace.vault.plist" >/dev/null 2>&1 || true
    launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/plus.svc.xworkspace.ttyd.plist" >/dev/null 2>&1 || true

    info "Starting LiteLLM on http://127.0.0.1:4000 ..."
    deploy_launch_agent \
        "plus.svc.xworkspace.litellm" \
        "$HOME" \
        "exec /usr/bin/env PATH='$tool_path' DATABASE_URL='$litellm_database_url' LITELLM_MASTER_KEY=\"\$(cat '$config_dir/auth-token')\" LITELLM_SALT_KEY=\"\$(cat '$config_dir/auth-token')\" UI_USERNAME=admin UI_PASSWORD=\"\$(cat '$config_dir/auth-token')\" '$litellm_bin' --host 127.0.0.1 --port 4000 --config '$litellm_config' --use_prisma_db_push" \
        "$state_dir/litellm.log" \
        "$state_dir/litellm.err.log"
    wait_for_url "http://127.0.0.1:4000/ui"

    info "Starting OpenClaw on http://127.0.0.1:18789/channels ..."
    deploy_launch_agent \
        "plus.svc.xworkspace.openclaw" \
        "$HOME" \
        "exec /usr/bin/env PATH='$tool_path' OPENCLAW_GATEWAY_TOKEN=\"\$(cat '$config_dir/auth-token')\" '$openclaw_bin' gateway run --dev --force --bind loopback --auth token --token \"\$(cat '$config_dir/auth-token')\" --port 18789" \
        "$state_dir/openclaw.log" \
        "$state_dir/openclaw.err.log"
    wait_for_url "http://127.0.0.1:18789/channels"

    info "Starting Vault on http://127.0.0.1:8200/ui ..."
    deploy_launch_agent \
        "plus.svc.xworkspace.vault" \
        "$HOME" \
        "exec /usr/bin/env PATH='$tool_path' VAULT_ADDR=http://127.0.0.1:8200 '$vault_bin' server -dev -dev-listen-address=127.0.0.1:8200 -dev-root-token-id=\"\$(cat '$config_dir/auth-token')\"" \
        "$state_dir/vault.log" \
        "$state_dir/vault.err.log"
    wait_for_url "http://127.0.0.1:8200/ui"

    info "Starting ttyd terminal on http://127.0.0.1:7681 ..."
    deploy_launch_agent \
        "plus.svc.xworkspace.ttyd" \
        "$HOME" \
        "exec /usr/bin/env PATH='$tool_path' '$ttyd_bin' -W -i 127.0.0.1 -p 7681 -w '$HOME' /bin/zsh -l" \
        "$state_dir/ttyd.log" \
        "$state_dir/ttyd.err.log"
    wait_for_url "http://127.0.0.1:7681/"
}

deploy_macos_local() {
    require_or_install_macos_cmds

    local token=$1
    local console_dir config_dir state_dir api_log dashboard_log api_err dashboard_err go_bin npm_bin node_bin tool_path
    console_dir="$(resolve_console_dir)"
    config_dir="$HOME/.config/xworkspace"
    state_dir="$HOME/.local/state/xworkspace"
    go_bin="$(command -v go)"
    npm_bin="$(command -v npm)"
    node_bin="$(command -v node)"
    tool_path="$(dirname "$node_bin"):$(dirname "$go_bin"):$(dirname "$npm_bin"):/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    mkdir -p "$state_dir"
    api_log="$state_dir/xworkspace-api.log"
    dashboard_log="$state_dir/xworkspace-console.log"
    api_err="$state_dir/xworkspace-api.err.log"
    dashboard_err="$state_dir/xworkspace-console.err.log"

    info "Deploying AI Workspace Portal locally on macOS from $console_dir"
    write_local_portal_config "$token" "$config_dir"

    stop_managed_pid "$state_dir/xworkspace-api.pid"
    stop_managed_pid "$state_dir/xworkspace-console.pid"
    launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/plus.svc.xworkspace.api.plist" >/dev/null 2>&1 || true
    launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/plus.svc.xworkspace.console.plist" >/dev/null 2>&1 || true
    launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/plus.svc.xworkspace.litellm.plist" >/dev/null 2>&1 || true
    launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/plus.svc.xworkspace.openclaw.plist" >/dev/null 2>&1 || true
    launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/plus.svc.xworkspace.vault.plist" >/dev/null 2>&1 || true
    launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/plus.svc.xworkspace.ttyd.plist" >/dev/null 2>&1 || true
    ensure_port_available_for_repo 8788 "$console_dir"
    ensure_port_available_for_repo 17000 "$console_dir"
    ensure_port_available_for_repo 4000 "$console_dir"
    ensure_port_available_for_repo 18789 "$console_dir"
    ensure_port_available_for_repo 8200 "$console_dir"
    ensure_port_available_for_repo 7681 "$console_dir"

    info "Building dashboard assets..."
    (cd "$console_dir/dashboard" && npm install && npm run build)

    start_macos_target_services "$config_dir" "$state_dir" "$tool_path"

    info "Starting xworkspace API on http://127.0.0.1:8788 ..."
    deploy_launch_agent \
        "plus.svc.xworkspace.api" \
        "$console_dir/api" \
        "exec /usr/bin/env PATH='$tool_path' XWORKSPACE_PORTAL_SERVICES_FILE='$config_dir/portal-services.json' '$go_bin' run ." \
        "$api_log" \
        "$api_err"
    wait_for_url "http://127.0.0.1:8788/auth/status"

    info "Starting AI Workspace Portal on http://127.0.0.1:17000 ..."
    deploy_launch_agent \
        "plus.svc.xworkspace.console" \
        "$console_dir/dashboard" \
        "exec /usr/bin/env PATH='$tool_path' '$npm_bin' run preview -- --host 127.0.0.1 --port 17000" \
        "$dashboard_log" \
        "$dashboard_err"
    wait_for_url "http://127.0.0.1:17000/"

    local status_ok status_bad
    status_ok="$(curl -sS -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $token" http://127.0.0.1:8788/portal/services)"
    status_bad="$(curl -sS -o /dev/null -w '%{http_code}' -H "Authorization: Bearer wrong-token" http://127.0.0.1:8788/portal/services)"
    [ "$status_ok" = "200" ] || error "Expected valid token to unlock portal services, got HTTP $status_ok"
    [ "$status_bad" = "401" ] || error "Expected invalid token to be rejected, got HTTP $status_bad"

    success "AI Workspace Portal is running at http://127.0.0.1:17000/"
    info "Use the same xworkmate-bridge token to unlock the Portal."
    info "Logs: $api_log, $api_err, $dashboard_log, and $dashboard_err"
}

info "Starting AI Workspace All-in-One Bootstrap..."

# 1. Install prerequisites (git, curl, ansible) if missing
OS_NAME="$(detect_os)"
if [ "$OS_NAME" = "darwin" ] && [ "${AI_WORKSPACE_DARWIN_MODE:-local}" = "local" ]; then
    UNIFIED_AUTH_TOKEN="$(resolve_unified_auth_token)"
    export AI_WORKSPACE_AUTH_TOKEN="$UNIFIED_AUTH_TOKEN"
    export XWORKSPACE_CONSOLE_AUTH_TOKEN="${XWORKSPACE_CONSOLE_AUTH_TOKEN:-$UNIFIED_AUTH_TOKEN}"
    export INTERNAL_SERVICE_TOKEN="${INTERNAL_SERVICE_TOKEN:-$UNIFIED_AUTH_TOKEN}"
    export BRIDGE_AUTH_TOKEN="${BRIDGE_AUTH_TOKEN:-$UNIFIED_AUTH_TOKEN}"
    export XWORKMATE_BRIDGE_AUTH_TOKEN="${XWORKMATE_BRIDGE_AUTH_TOKEN:-$UNIFIED_AUTH_TOKEN}"
    export LITELLM_MASTER_KEY="${LITELLM_MASTER_KEY:-$UNIFIED_AUTH_TOKEN}"
    export OPENCLAW_GATEWAY_TOKEN="${OPENCLAW_GATEWAY_TOKEN:-$UNIFIED_AUTH_TOKEN}"
    export VAULT_TOKEN="${VAULT_TOKEN:-$UNIFIED_AUTH_TOKEN}"
    export VAULT_SERVER_ROOT_ACCESS_TOKEN="${VAULT_SERVER_ROOT_ACCESS_TOKEN:-$UNIFIED_AUTH_TOKEN}"
    export VAULT_ADMIN_PASSWORD="${VAULT_ADMIN_PASSWORD:-$UNIFIED_AUTH_TOKEN}"
    deploy_macos_local "$UNIFIED_AUTH_TOKEN"
    exit 0
fi

if ! command -v ansible-playbook >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
    install_prerequisites "$OS_NAME"
fi

# 2. Clone Repository
if [ -n "$PLAYBOOK_DIR" ]; then
    [ -d "$PLAYBOOK_DIR" ] || error "PLAYBOOK_DIR does not exist: $PLAYBOOK_DIR"
    info "Using local playbooks repository at $PLAYBOOK_DIR"
    cd "$PLAYBOOK_DIR"
elif [ -d "$TARGET_DIR" ]; then
    info "Updating existing repository in $TARGET_DIR..."
    cd "$TARGET_DIR"
    git fetch origin
    git reset --hard origin/"$BRANCH"
else
    info "Cloning playbooks repository to $TARGET_DIR..."
    git clone -b "$BRANCH" "$REPO_URL" "$TARGET_DIR"
    cd "$TARGET_DIR"
fi

patch_playbook_user_systemd

# 3. Construct Ansible variables from Environment Variables
ANSIBLE_EXTRA_VARS=()

# Helper function to append to extra vars if set
append_var() {
    local env_name=$1
    local ansible_var=$2
    local val="${!env_name:-}"
    if [ -n "$val" ]; then
        info "Applying parameter: $ansible_var = $val"
        ANSIBLE_EXTRA_VARS+=("-e" "$ansible_var=$val")
    fi
}

append_secret_var() {
    local ansible_var=$1
    local val=$2
    if [ -n "$val" ]; then
        info "Applying secret parameter: $ansible_var = $(mask_secret "$val")"
        ANSIBLE_EXTRA_VARS+=("-e" "$ansible_var=$val")
    fi
}

append_var "AI_WORKSPACE_SECURITY_LEVEL"        "ai_workspace_security_level"
append_var "LITELLM_API_CADDY_STRICT_WHITELIST" "litellm_api_caddy_strict_whitelist"
append_var "XWORKSPACE_CONSOLE_PUBLIC_ACCESS"   "xworkspace_console_public_access"
append_var "XWORKMATE_BRIDGE_PUBLIC_ACCESS"     "xworkmate_bridge_public_access"
append_var "GATEWAY_OPENCLAW_PUBLIC_ACCESS"     "gateway_openclaw_public_access"
append_var "VAULT_PUBLIC_ACCESS"                "vault_public_access"
append_var "XWORKSPACE_CONSOLE_ENABLE_XRDP"     "xworkspace_console_enable_xrdp"

# 4. Resolve one auth token for the bridge and downstream service UIs/APIs.
UNIFIED_AUTH_TOKEN="$(resolve_unified_auth_token)"
append_secret_var "ai_workspace_auth_token" "$UNIFIED_AUTH_TOKEN"
append_secret_var "xworkspace_console_auth_token" "$UNIFIED_AUTH_TOKEN"
append_secret_var "xworkmate_bridge_auth_token" "$UNIFIED_AUTH_TOKEN"
append_secret_var "litellm_master_key" "$UNIFIED_AUTH_TOKEN"
append_secret_var "litellm_ui_password" "$UNIFIED_AUTH_TOKEN"
append_secret_var "gateway_openclaw_gateway_token" "$UNIFIED_AUTH_TOKEN"
append_secret_var "vault_server_root_access_token" "$UNIFIED_AUTH_TOKEN"
append_secret_var "vault_root_token" "$UNIFIED_AUTH_TOKEN"
append_secret_var "vault_admin_password" "$UNIFIED_AUTH_TOKEN"
ANSIBLE_EXTRA_VARS+=("-e" "vault_admin_init_enabled=true")

# Export environment fallbacks for roles/scripts that read environment directly.
export AI_WORKSPACE_AUTH_TOKEN="$UNIFIED_AUTH_TOKEN"
export XWORKSPACE_CONSOLE_AUTH_TOKEN="${XWORKSPACE_CONSOLE_AUTH_TOKEN:-$UNIFIED_AUTH_TOKEN}"
export INTERNAL_SERVICE_TOKEN="${INTERNAL_SERVICE_TOKEN:-$UNIFIED_AUTH_TOKEN}"
export BRIDGE_AUTH_TOKEN="${BRIDGE_AUTH_TOKEN:-$UNIFIED_AUTH_TOKEN}"
export XWORKMATE_BRIDGE_AUTH_TOKEN="${XWORKMATE_BRIDGE_AUTH_TOKEN:-$UNIFIED_AUTH_TOKEN}"
export LITELLM_MASTER_KEY="${LITELLM_MASTER_KEY:-$UNIFIED_AUTH_TOKEN}"
export OPENCLAW_GATEWAY_TOKEN="${OPENCLAW_GATEWAY_TOKEN:-$UNIFIED_AUTH_TOKEN}"
export VAULT_TOKEN="${VAULT_TOKEN:-$UNIFIED_AUTH_TOKEN}"
export VAULT_SERVER_ROOT_ACCESS_TOKEN="${VAULT_SERVER_ROOT_ACCESS_TOKEN:-$UNIFIED_AUTH_TOKEN}"
export VAULT_ADMIN_PASSWORD="${VAULT_ADMIN_PASSWORD:-$UNIFIED_AUTH_TOKEN}"

# 5. Handle Ansible Vault password.
# Keep this separate from the runtime auth token, but reuse DEPLOY_TOKEN for
# backward compatibility when no explicit vault password is provided.
if [ -n "${ANSIBLE_VAULT_PASSWORD:-}" ]; then
    printf '%s' "$ANSIBLE_VAULT_PASSWORD" > "$VAULT_FILE"
    info "Using provided ANSIBLE_VAULT_PASSWORD for Ansible Vault."
elif [ -n "${DEPLOY_TOKEN:-}" ]; then
    printf '%s' "$DEPLOY_TOKEN" > "$VAULT_FILE"
    info "Using DEPLOY_TOKEN as the Ansible Vault password for backward compatibility."
elif [ -f "$VAULT_FILE" ]; then
    info "Found existing Ansible Vault password at $VAULT_FILE, reusing it."
else
    info "No Ansible Vault password provided. Generating a secure random password..."
    openssl rand -base64 32 > "$VAULT_FILE"
    info "Generated new Ansible Vault password and saved to $VAULT_FILE"
fi

# Ensure correct permissions for the vault file
chmod 600 "$VAULT_FILE"

# 6. Run Ansible Playbook locally
info "Running Ansible Playbook locally..."
ansible-playbook -i '127.0.0.1,' -c local setup-ai-workspace-all-in-one.yml \
    --vault-password-file "$VAULT_FILE" \
    "${ANSIBLE_EXTRA_VARS[@]}"
RET=$?

if [ $RET -eq 0 ]; then
    success "AI Workspace deployed successfully!"
    print_deployment_summary "$UNIFIED_AUTH_TOKEN"
else
    error "Deployment failed with exit code $RET."
fi
