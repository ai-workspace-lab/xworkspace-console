#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# AI Workspace All-in-One Bootstrap Script
# ==============================================================================
# Usage:
#   curl -sfL https://raw.githubusercontent.com/ai-workspace-lab/xworkspace-console/main/scripts/setup-ai-workspace-all-in-one.sh | bash -
#
# Supported Environment Variables:
#   AI_WORKSPACE_SECURITY_LEVEL
#   LITELLM_API_CADDY_STRICT_WHITELIST
#   LITELLM_CADDY_CONFIG_ENABLED
#   XWORKSPACE_CONSOLE_PUBLIC_ACCESS
#   XWORKMATE_BRIDGE_PUBLIC_ACCESS
#   GATEWAY_OPENCLAW_PUBLIC_ACCESS
#   VAULT_PUBLIC_ACCESS
#   XWORKSPACE_CONSOLE_ENABLE_XRDP
#   AI_WORKSPACE_RUNTIME_MODES (docker,systemd by default; docker and k3s are mutually exclusive)
#   POSTGRESQL_DEPLOY_MODE (compose by default; native for apt/systemd)
#   AI_WORKSPACE_AUTH_TOKEN / XWORKSPACE_CONSOLE_AUTH_TOKEN
#     / XWORKMATE_BRIDGE_AUTH_TOKEN / BRIDGE_AUTH_TOKEN / INTERNAL_SERVICE_TOKEN
#     / DEPLOY_TOKEN
#       Unified auth token passed to xworkmate-bridge, LiteLLM, OpenClaw, and Vault.
#   PLAYBOOK_DIR (optional local playbooks checkout; useful for macOS validation)
#   XWORKSPACE_CONSOLE_DIR (optional local xworkspace-console checkout for macOS)
#   XWORKSPACE_CONSOLE_SOURCE_REPO / XWORKSPACE_CONSOLE_SOURCE_VERSION
#     (optional Git source used by the Linux console playbook)
#   XWORKSPACE_CONSOLE_RUNTIME_ARCHIVE / QMD_RUNTIME_ARCHIVE
#   LITELLM_PACKAGE_SPEC / AI_WORKSPACE_PREBUILT_COMPONENTS_REQUIRED
#   OPENCLAW_MULTI_SESSION_PLUGIN_PACKAGE_SPEC
#     Optional OpenClaw plugin source for XWorkmate session/artifact methods.
#   OPENCLAW_MULTI_SESSION_PLUGIN_DIR
#     Optional local checkout used for macOS OpenClaw link install.
#   AI_WORKSPACE_OFFLINE_MODE=auto (default) | force | off
#   AI_WORKSPACE_OFFLINE_PACKAGE (local tarball/directory or URL)
#   AI_WORKSPACE_OFFLINE_PACKAGE_URL (direct tarball URL)
#   AI_WORKSPACE_OFFLINE_PACKAGE_BASE_URL (mirror directory containing target tarball)
#   AI_WORKSPACE_OFFLINE_RELEASE_TAG=latest (GitHub release tag or latest)
#   AI_WORKSPACE_OFFLINE_REPO=ai-workspace-lab/xworkspace-console
#   AI_WORKSPACE_OFFLINE_AUTO_DOWNLOAD=true (download matching GitHub release package in auto mode)
#   AI_WORKSPACE_OFFLINE_WORK_DIR=/tmp/ai-workspace-offline
#   AI_WORKSPACE_DEPLOYMENT_LOCK_TIMEOUT=1800
#   AI_WORKSPACE_APT_LOCK_TIMEOUT=900
#   AI_WORKSPACE_PREFETCH_ENABLED=true
#   AI_WORKSPACE_MAX_PARALLEL_JOBS=auto (never exceeds 2 x online CPU cores)
#   AI_WORKSPACE_PREFETCH_DIR=/var/tmp/ai-workspace-prefetch
#   AI_WORKSPACE_SPLIT_PHASES=true
#   AI_WORKSPACE_RUNTIME_PREBUILD_ENABLED=false
#   AI_WORKSPACE_DARWIN_MODE=local (default on macOS) | ansible
# ==============================================================================

REPO_URL=${REPO_URL:-"https://github.com/ai-workspace-infra/playbooks.git"}
BRANCH=${BRANCH:-"main"}
TARGET_DIR=${TARGET_DIR:-"/tmp/ai-workspace-deploy"}
PLAYBOOK_DIR=${PLAYBOOK_DIR:-""}
XWORKSPACE_CONSOLE_REPO_URL=${XWORKSPACE_CONSOLE_REPO_URL:-"https://github.com/ai-workspace-lab/xworkspace-console.git"}
XWORKSPACE_CONSOLE_DIR=${XWORKSPACE_CONSOLE_DIR:-""}
if [ -z "$XWORKSPACE_CONSOLE_DIR" ]; then
    # Try to auto-detect if we are running inside a local checkout on macOS
    _script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null || pwd)"
    if [ -d "$_script_dir/../api" ] && [ -d "$_script_dir/../dashboard" ]; then
        XWORKSPACE_CONSOLE_DIR="$(dirname "$_script_dir")"
    else
        XWORKSPACE_CONSOLE_DIR="$HOME/xworkspace-console"
    fi
fi
XWORKSPACE_CORE_SKILLS_REPO_URL=${XWORKSPACE_CORE_SKILLS_REPO_URL:-"https://github.com/ai-workspace-lab/xworkspace-core-skills.git"}
XWORKSPACE_CORE_SKILLS_DIR=${XWORKSPACE_CORE_SKILLS_DIR:-"/tmp/xworkspace-core-skills"}
XWORKMATE_BRIDGE_REPO_URL=${XWORKMATE_BRIDGE_REPO_URL:-"https://github.com/ai-workspace-lab/xworkmate-bridge.git"}
XWORKMATE_BRIDGE_BRANCH=${XWORKMATE_BRIDGE_BRANCH:-"release/v1.1.4"}
XWORKMATE_BRIDGE_SOURCE_DIR=${XWORKMATE_BRIDGE_SOURCE_DIR:-"/tmp/xworkmate-bridge"}
OPENCLAW_MULTI_SESSION_PLUGIN_PACKAGE_SPEC=${OPENCLAW_MULTI_SESSION_PLUGIN_PACKAGE_SPEC:-"github:x-evor/openclaw-multi-session-plugins#main"}
OPENCLAW_MULTI_SESSION_PLUGIN_DIR=${OPENCLAW_MULTI_SESSION_PLUGIN_DIR:-""}
if [ -z "$OPENCLAW_MULTI_SESSION_PLUGIN_DIR" ]; then
    _script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null || pwd)"
    if [ -d "$_script_dir/../../openclaw-multi-session-plugins" ]; then
        OPENCLAW_MULTI_SESSION_PLUGIN_DIR="$(cd "$_script_dir/../../openclaw-multi-session-plugins" && pwd)"
    else
        OPENCLAW_MULTI_SESSION_PLUGIN_DIR="/tmp/openclaw-multi-session-plugins"
    fi
fi
AUTH_TOKEN_FILE=${AI_WORKSPACE_AUTH_TOKEN_FILE:-"$HOME/.ai_workspace_auth_token"}
AI_WORKSPACE_LITELLM_PORT=${AI_WORKSPACE_LITELLM_PORT:-"4000"}
AI_WORKSPACE_DEFAULT_MODEL=${AI_WORKSPACE_DEFAULT_MODEL:-"deepseek/deepseek-v4-flash"}
AI_WORKSPACE_FALLBACK_MODEL=${AI_WORKSPACE_FALLBACK_MODEL:-"deepseek/deepseek-v4-pro"}
VAULT_FILE=${AI_WORKSPACE_VAULT_PASSWORD_FILE:-"$HOME/.vault_password"}
AI_WORKSPACE_OFFLINE_MODE=${AI_WORKSPACE_OFFLINE_MODE:-"auto"}
AI_WORKSPACE_OFFLINE_REPO=${AI_WORKSPACE_OFFLINE_REPO:-"ai-workspace-lab/xworkspace-console"}
AI_WORKSPACE_OFFLINE_RELEASE_TAG=${AI_WORKSPACE_OFFLINE_RELEASE_TAG:-"latest"}
if [ -z "${AI_WORKSPACE_OFFLINE_WORK_DIR:-}" ]; then
    if command -v df >/dev/null 2>&1; then
        _largest_mount=$(df -P -x tmpfs -x devtmpfs -x squashfs -x overlay 2>/dev/null | awk 'NR>1 {print $4, $6}' | sort -nr | head -n1 | awk '{print $2}' || true)
        if [ -n "$_largest_mount" ] && [ "$_largest_mount" != "/" ]; then
            AI_WORKSPACE_OFFLINE_WORK_DIR="${_largest_mount}/ai-workspace-offline"
        else
            AI_WORKSPACE_OFFLINE_WORK_DIR="/var/tmp/ai-workspace-offline"
        fi
    else
        AI_WORKSPACE_OFFLINE_WORK_DIR="/var/tmp/ai-workspace-offline"
    fi
fi
AI_WORKSPACE_DEPLOYMENT_LOCK_TIMEOUT=${AI_WORKSPACE_DEPLOYMENT_LOCK_TIMEOUT:-"1800"}
AI_WORKSPACE_APT_LOCK_TIMEOUT=${AI_WORKSPACE_APT_LOCK_TIMEOUT:-"900"}
AI_WORKSPACE_PREFETCH_ENABLED=${AI_WORKSPACE_PREFETCH_ENABLED:-"true"}
AI_WORKSPACE_MAX_PARALLEL_JOBS=${AI_WORKSPACE_MAX_PARALLEL_JOBS:-"auto"}
AI_WORKSPACE_PREFETCH_DIR=${AI_WORKSPACE_PREFETCH_DIR:-"/var/tmp/ai-workspace-prefetch"}
AI_WORKSPACE_SPLIT_PHASES=${AI_WORKSPACE_SPLIT_PHASES:-"true"}
AI_WORKSPACE_RUNTIME_PREBUILD_ENABLED=${AI_WORKSPACE_RUNTIME_PREBUILD_ENABLED:-"false"}
BOUNDED_JOB_PIDS=()
BOUNDED_JOB_LABELS=()
BOUNDED_JOB_FAILED=0
PARALLEL_LIMIT_WARNING_EMITTED=false

# Function: Output messages
info() {
    echo -e "\033[1;34m[INFO]\033[0m $*" >&2
}
success() {
    echo -e "\033[1;32m[SUCCESS]\033[0m $*" >&2
}
warn() {
    echo -e "\033[1;33m[WARN]\033[0m $*" >&2
}
error() {
    echo -e "\033[1;31m[ERROR]\033[0m $*" >&2
    exit 1
}

reset_bounded_jobs() {
    BOUNDED_JOB_PIDS=()
    BOUNDED_JOB_LABELS=()
    BOUNDED_JOB_FAILED=0
}

validate_parallel_job_limit() {
    case "$AI_WORKSPACE_MAX_PARALLEL_JOBS" in
        auto) ;;
        ''|*[!0-9]*|0) error "AI_WORKSPACE_MAX_PARALLEL_JOBS must be auto or a positive integer." ;;
    esac
}

online_cpu_count() {
    local count=""
    if command -v getconf >/dev/null 2>&1; then
        count="$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)"
    fi
    if [ -z "$count" ] && command -v nproc >/dev/null 2>&1; then
        count="$(nproc 2>/dev/null || true)"
    fi
    if [ -z "$count" ] && command -v sysctl >/dev/null 2>&1; then
        count="$(sysctl -n hw.logicalcpu 2>/dev/null || true)"
    fi
    case "$count" in
        ''|*[!0-9]*|0) count=1 ;;
    esac
    printf '%s\n' "$count"
}

one_minute_load_average() {
    if [ -r /proc/loadavg ]; then
        awk '{print $1}' /proc/loadavg
        return
    fi
    if command -v sysctl >/dev/null 2>&1; then
        sysctl -n vm.loadavg 2>/dev/null | awk '{gsub(/[{}]/, ""); print $1}'
        return
    fi
    printf '0\n'
}

dynamic_parallel_job_limit() {
    local cpu_count hard_limit configured_limit load_average load_ceiling dynamic_limit
    cpu_count="$(online_cpu_count)"
    hard_limit=$((cpu_count * 2))
    configured_limit="$hard_limit"
    if [ "$AI_WORKSPACE_MAX_PARALLEL_JOBS" != "auto" ]; then
        configured_limit="$AI_WORKSPACE_MAX_PARALLEL_JOBS"
        if [ "$configured_limit" -gt "$hard_limit" ]; then
            configured_limit="$hard_limit"
            if [ "$PARALLEL_LIMIT_WARNING_EMITTED" = "false" ]; then
                warn "Parallel job limit was capped at ${hard_limit} (2 x ${cpu_count} online CPU cores)."
                PARALLEL_LIMIT_WARNING_EMITTED=true
            fi
        fi
    fi

    load_average="$(one_minute_load_average)"
    load_ceiling="$(awk -v average="$load_average" 'BEGIN { value=int(average); if (average > value) value++; print value }')"
    dynamic_limit=$((hard_limit - load_ceiling))
    if [ "$dynamic_limit" -lt 1 ]; then
        dynamic_limit=1
    fi
    if [ "$dynamic_limit" -gt "$configured_limit" ]; then
        dynamic_limit="$configured_limit"
    fi
    printf '%s\n' "$dynamic_limit"
}

wait_for_bounded_job() {
    local index=$1
    local pid="${BOUNDED_JOB_PIDS[$index]}"
    local label="${BOUNDED_JOB_LABELS[$index]}"

    if wait "$pid"; then
        info "Parallel job completed: $label"
    else
        warn "Parallel job failed: $label"
        BOUNDED_JOB_FAILED=1
    fi
    unset 'BOUNDED_JOB_PIDS[index]'
    unset 'BOUNDED_JOB_LABELS[index]'
    BOUNDED_JOB_PIDS=("${BOUNDED_JOB_PIDS[@]}")
    BOUNDED_JOB_LABELS=("${BOUNDED_JOB_LABELS[@]}")
}

run_bounded() {
    local label=$1
    local dynamic_limit
    shift

    validate_parallel_job_limit
    dynamic_limit="$(dynamic_parallel_job_limit)"
    while [ "${#BOUNDED_JOB_PIDS[@]}" -ge "$dynamic_limit" ]; do
        wait_for_bounded_job 0
        dynamic_limit="$(dynamic_parallel_job_limit)"
    done

    (
        set -o pipefail
        "$@" 2>&1 | sed "s/^/[${label}] /"
    ) &
    BOUNDED_JOB_PIDS+=("$!")
    BOUNDED_JOB_LABELS+=("$label")
}

wait_for_bounded_jobs() {
    while [ "${#BOUNDED_JOB_PIDS[@]}" -gt 0 ]; do
        wait_for_bounded_job 0
    done
    [ "$BOUNDED_JOB_FAILED" -eq 0 ]
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

if command -v git >/dev/null 2>&1; then
    git config --global --add safe.directory '*' || true
fi

detect_os() {
    case "$(uname -s)" in
        Darwin) echo "darwin" ;;
        Linux) echo "linux" ;;
        *) echo "unknown" ;;
    esac
}

run_as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        error "Root privileges are required to run: $*. Install sudo or rerun this script as root."
    fi
}

acquire_deployment_lock() {
    if [ "${AI_WORKSPACE_DEPLOYMENT_LOCK_HELD:-false}" = "true" ]; then
        return
    fi
    if ! command -v flock >/dev/null 2>&1; then
        warn "flock is unavailable; continuing without the deployment serialization lock."
        return
    fi

    local lock_file="${AI_WORKSPACE_DEPLOYMENT_LOCK_FILE:-/var/lock/ai-workspace-all-in-one.lock}"
    if [ "$(id -u)" -ne 0 ]; then
        lock_file="${AI_WORKSPACE_DEPLOYMENT_LOCK_FILE:-${TMPDIR:-/tmp}/ai-workspace-all-in-one-${UID}.lock}"
    fi
    mkdir -p "$(dirname "$lock_file")"
    exec 9>"$lock_file"
    info "Waiting for the AI Workspace deployment lock: $lock_file"
    if ! flock -w "$AI_WORKSPACE_DEPLOYMENT_LOCK_TIMEOUT" 9; then
        error "Timed out waiting for another AI Workspace deployment to finish."
    fi
    export AI_WORKSPACE_DEPLOYMENT_LOCK_HELD=true
}

wait_for_apt_locks() {
    if [ ! -f /etc/debian_version ]; then
        return
    fi

    local timeout="${AI_WORKSPACE_APT_LOCK_TIMEOUT:-900}"
    local waited=0
    local busy
    while true; do
        busy=false
        if pgrep -x apt-get >/dev/null 2>&1 ||
           pgrep -x apt >/dev/null 2>&1 ||
           pgrep -x dpkg >/dev/null 2>&1 ||
           pgrep -x unattended-upgrade >/dev/null 2>&1; then
            busy=true
        fi
        local lock
        for lock in \
            /var/lib/dpkg/lock-frontend \
            /var/lib/dpkg/lock \
            /var/lib/apt/lists/lock \
            /var/cache/apt/archives/lock; do
            if [ "$busy" = "false" ] &&
               command -v fuser >/dev/null 2>&1 &&
               [ -e "$lock" ] &&
               fuser "$lock" >/dev/null 2>&1; then
                busy=true
            fi
            if [ "$busy" = "false" ] &&
               command -v lslocks >/dev/null 2>&1 &&
               lslocks -rn -o PATH 2>/dev/null | grep -Fxq "$lock"; then
                busy=true
            fi
        done

        if [ "$busy" = "false" ]; then
            return
        fi
        if [ "$waited" -ge "$timeout" ]; then
            error "Timed out after ${timeout}s waiting for APT/dpkg locks."
        fi
        if [ $((waited % 30)) -eq 0 ]; then
            info "Another package manager is active; waiting for APT/dpkg locks (${waited}s/${timeout}s)..."
        fi
        sleep 5
        waited=$((waited + 5))
    done
}

install_prerequisites() {
    local os="$1"
    info "Installing required dependencies (git, ansible)..."
    if [ "$os" = "linux" ]; then
        if [ -f /etc/debian_version ]; then
            run_as_root apt-get update -y
            if grep -qi ubuntu /etc/os-release 2>/dev/null; then
                run_as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y git curl software-properties-common
                run_as_root apt-add-repository --yes --update ppa:ansible/ansible
                run_as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y ansible
            else
                run_as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y git curl ansible
            fi
        elif [ -f /etc/redhat-release ]; then
            run_as_root yum install -y epel-release
            run_as_root yum install -y git curl ansible
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

ensure_public_edge_firewall_ports() {
    if [ "$(detect_os)" != "linux" ]; then
        return
    fi

    local sudo_cmd=()
    if [ "$(id -u)" -ne 0 ]; then
        sudo_cmd=(sudo)
    fi

    if command -v ufw >/dev/null 2>&1; then
        local ufw_status
        ufw_status="$(ufw status 2>/dev/null || "${sudo_cmd[@]}" ufw status 2>/dev/null || true)"
        if printf '%s\n' "$ufw_status" | grep -qi '^Status:[[:space:]]*active'; then
            info "UFW is active; allowing SSH, HTTP, and HTTPS ingress for AI Workspace."
            "${sudo_cmd[@]}" ufw allow 22/tcp >/dev/null || warn "Unable to allow 22/tcp in UFW."
            "${sudo_cmd[@]}" ufw allow 80/tcp >/dev/null || warn "Unable to allow 80/tcp in UFW."
            "${sudo_cmd[@]}" ufw allow 443/tcp >/dev/null || warn "Unable to allow 443/tcp in UFW."
        else
            info "UFW is not active; no UFW ingress changes required."
        fi
    fi

    if command -v firewall-cmd >/dev/null 2>&1; then
        local firewalld_state
        firewalld_state="$(firewall-cmd --state 2>/dev/null || "${sudo_cmd[@]}" firewall-cmd --state 2>/dev/null || true)"
        if [ "$firewalld_state" = "running" ]; then
            info "firewalld is running; allowing SSH, HTTP, and HTTPS ingress for AI Workspace."
            "${sudo_cmd[@]}" firewall-cmd --permanent --add-service=ssh >/dev/null || warn "Unable to allow ssh in firewalld."
            "${sudo_cmd[@]}" firewall-cmd --permanent --add-service=http >/dev/null || warn "Unable to allow http in firewalld."
            "${sudo_cmd[@]}" firewall-cmd --permanent --add-service=https >/dev/null || warn "Unable to allow https in firewalld."
            "${sudo_cmd[@]}" firewall-cmd --reload >/dev/null || warn "Unable to reload firewalld."
        fi
    fi
}

offline_mode_is_force() {
    case "$(printf '%s' "${AI_WORKSPACE_OFFLINE_MODE:-auto}" | tr '[:upper:]' '[:lower:]')" in
        force|required|true|1|yes) return 0 ;;
        *) return 1 ;;
    esac
}

offline_mode_is_off() {
    case "$(printf '%s' "${AI_WORKSPACE_OFFLINE_MODE:-auto}" | tr '[:upper:]' '[:lower:]')" in
        off|disabled|false|0|no) return 0 ;;
        *) return 1 ;;
    esac
}

offline_fail_or_fallback() {
    local message=$1
    if offline_mode_is_force; then
        error "$message"
    fi
    warn "$message Falling back to online bootstrap."
    return 1
}

detect_offline_arch() {
    case "$(uname -m)" in
        x86_64|amd64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        *) return 1 ;;
    esac
}

detect_offline_target() {
    if [ ! -f /etc/os-release ]; then
        return 1
    fi

    # shellcheck disable=SC1091
    . /etc/os-release
    local distro="${AI_WORKSPACE_OFFLINE_DISTRO_ID:-${ID:-}}"
    local version="${AI_WORKSPACE_OFFLINE_DISTRO_VERSION:-${VERSION_ID:-}}"
    local arch="${AI_WORKSPACE_OFFLINE_ARCH:-}"

    if [ -z "$arch" ]; then
        arch="$(detect_offline_arch)" || return 1
    fi

    case "${distro}:${version}" in
        debian:11|debian:12|debian:13|ubuntu:22.04|ubuntu:24.04|ubuntu:26.04) ;;
        *) return 1 ;;
    esac

    printf '%s %s %s\n' "$distro" "$version" "$arch"
}

github_api() {
    local path=$1
    local headers=(-H "Accept: application/vnd.github+json")
    if [ -n "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]; then
        headers+=(-H "Authorization: Bearer ${GH_TOKEN:-${GITHUB_TOKEN}}")
    fi
    curl -fsSL --retry 5 --retry-all-errors "${headers[@]}" "https://api.github.com${path}"
}

offline_package_filename() {
    local target=$1
    # shellcheck disable=SC2086
    set -- $target
    printf 'ai-workspace-all-in-one-offline-%s-%s-%s.tar.gz\n' "$1" "$2" "$3"
}

resolve_offline_release_tag() {
    local filename=$1
    local repo="${AI_WORKSPACE_OFFLINE_REPO:-ai-workspace-lab/xworkspace-console}"
    local requested_tag="${AI_WORKSPACE_OFFLINE_RELEASE_TAG:-latest}"
    local tag=""

    if [ "$requested_tag" != "latest" ]; then
        printf '%s\n' "$requested_tag"
        return
    fi

    tag="$(
        github_api "/repos/${repo}/releases?per_page=100" |
            jq -r --arg name "${filename}" '
                [ .[]
                  | select(.draft == false)
                  | select(any(.assets[]?; .name == $name))
                  | .tag_name
                ][0] // empty
            '
    )"

    [ -n "$tag" ] && printf '%s\n' "$tag"
}

offline_release_url() {
    local filename=$1
    local tag
    tag="$(resolve_offline_release_tag "$filename")"
    if [ -z "$tag" ]; then
        tag="${AI_WORKSPACE_OFFLINE_RELEASE_TAG:-latest}"
    fi
    if [ "$tag" = "latest" ]; then
        printf 'https://github.com/%s/releases/latest/download/%s\n' "$AI_WORKSPACE_OFFLINE_REPO" "$filename"
    else
        printf 'https://github.com/%s/releases/download/%s/%s\n' "$AI_WORKSPACE_OFFLINE_REPO" "$tag" "$filename"
    fi
}

offline_package_source() {
    local filename=$1
    if [ -n "${AI_WORKSPACE_OFFLINE_PACKAGE:-}" ]; then
        printf '%s\n' "$AI_WORKSPACE_OFFLINE_PACKAGE"
        return
    fi
    if [ -n "${AI_WORKSPACE_OFFLINE_PACKAGE_URL:-}" ]; then
        printf '%s\n' "$AI_WORKSPACE_OFFLINE_PACKAGE_URL"
        return
    fi
    if [ -n "${AI_WORKSPACE_OFFLINE_PACKAGE_BASE_URL:-}" ]; then
        printf '%s/%s\n' "${AI_WORKSPACE_OFFLINE_PACKAGE_BASE_URL%/}" "$filename"
        return
    fi
    if [ "${AI_WORKSPACE_OFFLINE_AUTO_DOWNLOAD:-true}" = "true" ]; then
        offline_release_url "$filename"
    fi
}

resolve_offline_source_url() {
    local source=$1
    local location

    case "$source" in
        https://github.com/*/releases/latest/download/*)
            location="$(
                curl -sSI --connect-timeout 15 --max-time 30 "$source" 2>/dev/null |
                    tr -d '\r' |
                    awk 'tolower($1) == "location:" { print $2; exit }'
            )"
            if [ -n "$location" ]; then
                printf '%s\n' "$location"
            else
                printf '%s\n' "$source"
            fi
            ;;
        *) printf '%s\n' "$source" ;;
    esac
}

source_cache_key() {
    local source=$1
    printf '%s' "$source" | sha256_stream | cut -c1-16
}

sha256_stream() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum | awk '{print $1}'
        return
    fi
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 | awk '{print $1}'
        return
    fi
    return 1
}

offline_root_from_dir() {
    local dir=$1
    if [ -f "$dir/scripts/ai-workspace-offline-install.sh" ]; then
        cd "$dir"
        pwd
        return
    fi
    return 1
}

extract_offline_package() {
    local package=$1
    local extract_dir="$AI_WORKSPACE_OFFLINE_WORK_DIR/extracted"
    local installer archive_checksum cached_checksum cached_root

    validate_offline_archive "$package" || return 1
    archive_checksum="$(sha256_file "$package")" || return 1
    cached_checksum="$(cat "$extract_dir/.archive-sha256" 2>/dev/null || true)"
    cached_root="$(cat "$extract_dir/.package-root" 2>/dev/null || true)"
    if [ "$cached_checksum" = "$archive_checksum" ] &&
       [ -n "$cached_root" ] &&
       [ -f "$cached_root/scripts/ai-workspace-offline-install.sh" ]; then
        info "Reusing extracted AI Workspace offline package: $cached_root"
        printf '%s\n' "$cached_root"
        return
    fi

    rm -rf "$extract_dir"
    mkdir -p "$extract_dir"
    tar -xzf "$package" -C "$extract_dir"
    installer="$(find "$extract_dir" -mindepth 2 -maxdepth 3 -type f -path '*/scripts/ai-workspace-offline-install.sh' -print -quit)"
    if [ -z "$installer" ]; then
        return 1
    fi
    cached_root="$(cd "$(dirname "$installer")/.." && pwd)"
    printf '%s\n' "$archive_checksum" > "$extract_dir/.archive-sha256"
    printf '%s\n' "$cached_root" > "$extract_dir/.package-root"
    printf '%s\n' "$cached_root"
}

sha256_file() {
    local file=$1
    sha256_stream < "$file"
}

validate_offline_archive() {
    local package=$1
    local contents="$AI_WORKSPACE_OFFLINE_WORK_DIR/archive-contents.txt"

    [ -f "$package" ] || return 1
    tar -tzf "$package" > "$contents" || return 1
    if awk '
        /^\/+/ { exit 1 }
        /(^|\/)\.\.(\/|$)/ { exit 1 }
    ' "$contents"; then
        return 0
    fi
    warn "Offline package contains an unsafe archive path: $package"
    return 1
}

download_offline_split() {
    # Reassemble an offline package that was published as <2 GiB parts because it
    # exceeded GitHub's 2 GiB asset cap. "$source" is the would-be single-file
    # URL; the parts manifest lives at "${source}.parts" and lists the part asset
    # names (one per line), which sit next to it in the same release.
    local source=$1
    local partial=$2
    local base manifest part part_url
    base="${source%/*}"
    manifest="${partial}.parts"
    curl -fL --retry 3 --retry-delay 5 -o "$manifest" "${source}.parts" 2>/dev/null || return 1
    : > "$partial"
    while IFS= read -r part; do
        part="${part%$'\r'}"
        [ -n "$part" ] || continue
        part_url="${base}/${part}"
        info "Downloading AI Workspace offline package part: ${part}"
        if ! curl -fL --retry 3 --retry-delay 5 "$part_url" >> "$partial"; then
            rm -f "$manifest"
            return 1
        fi
    done < "$manifest"
    rm -f "$manifest"
    return 0
}

prepare_offline_package_root() {
    local source=$1
    local filename=$2
    local resolved_source cache_key package
    resolved_source="$(resolve_offline_source_url "$source")"
    cache_key="$(source_cache_key "$resolved_source")" || return 1
    package="$AI_WORKSPACE_OFFLINE_WORK_DIR/${cache_key}-${filename}"
    local partial="${package}.part"

    mkdir -p "$AI_WORKSPACE_OFFLINE_WORK_DIR"

    case "$source" in
        http://*|https://*)
            command -v curl >/dev/null 2>&1 || return 1
            if validate_offline_archive "$package" 2>/dev/null; then
                info "Reusing cached AI Workspace offline package: $package"
            else
                info "Downloading AI Workspace offline package: $resolved_source"
                if ! curl -fL --retry 3 --retry-delay 5 --continue-at - -o "$partial" "$resolved_source" 2>/dev/null \
                   && ! curl -fL --retry 3 --retry-delay 5 -o "$partial" "$resolved_source" 2>/dev/null; then
                    # The single asset may have been split into <2 GiB parts.
                    rm -f "$partial"
                    info "Single offline asset unavailable; trying split parts..."
                    download_offline_split "$source" "$partial" || return 1
                fi
                validate_offline_archive "$partial" || return 1
                mv "$partial" "$package"
            fi
            extract_offline_package "$package"
            ;;
        *)
            if offline_root_from_dir "$source" 2>/dev/null; then
                return
            fi
            if [ ! -f "$source" ]; then
                return 1
            fi
            extract_offline_package "$source"
            ;;
    esac
}

manifest_target_value() {
    local manifest=$1
    local key=$2
    awk -v key="$key" '
        /"target"[[:space:]]*:/ { in_target=1; next }
        in_target && /^[[:space:]]*}/ { exit }
        in_target && $0 ~ "\"" key "\"[[:space:]]*:" {
            value=$0
            sub(/^.*:[[:space:]]*"/, "", value)
            sub(/".*$/, "", value)
            print value
            exit
        }
    ' "$manifest"
}

validate_offline_package_target() {
    local root=$1
    local target=$2
    local expected_distro expected_version expected_arch
    local package_distro package_version package_arch

    # shellcheck disable=SC2086
    set -- $target
    expected_distro=$1
    expected_version=$2
    expected_arch=$3

    if [ -f "$root/metadata/target.env" ]; then
        package_distro="$(sed -n 's/^DISTRO_ID=//p' "$root/metadata/target.env" | head -n 1)"
        package_version="$(sed -n 's/^DISTRO_VERSION=//p' "$root/metadata/target.env" | head -n 1)"
        package_arch="$(sed -n 's/^ARCH=//p' "$root/metadata/target.env" | head -n 1)"
    elif [ -f "$root/metadata/manifest.json" ]; then
        package_distro="$(manifest_target_value "$root/metadata/manifest.json" distro)"
        package_version="$(manifest_target_value "$root/metadata/manifest.json" version)"
        package_arch="$(manifest_target_value "$root/metadata/manifest.json" arch)"
    elif [ "${AI_WORKSPACE_OFFLINE_ALLOW_UNVERIFIED_TARGET:-false}" = "true" ]; then
        warn "Offline package has no target metadata; proceeding by explicit override."
        return
    else
        error "Offline package is missing metadata/target.env and metadata/manifest.json."
    fi

    if [ "$package_distro" != "$expected_distro" ] ||
       [ "$package_version" != "$expected_version" ] ||
       [ "$package_arch" != "$expected_arch" ]; then
        error "Offline package target ${package_distro}:${package_version}:${package_arch} does not match host ${expected_distro}:${expected_version}:${expected_arch}."
    fi
}

validate_offline_package_requirements() {
    local root=$1
    local target=$2

    case "$target" in
        "ubuntu 26.04 "*)
            if ! compgen -G "$root/packages/apt/npm_*.deb" >/dev/null; then
                warn "Ubuntu 26.04 offline package is missing the required standalone npm package."
                return 1
            fi
            ;;
    esac
}

ensure_git_for_offline_refresh() {
    local target=$1

    command -v git >/dev/null 2>&1 && return

    case "$target" in
        "ubuntu "*|"debian "*)
            info "Installing Git before refreshing packaged repositories..."
            wait_for_apt_locks
            run_as_root apt-get update -y
            run_as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y git
            ;;
        *)
            return
            ;;
    esac
}

refresh_offline_package_repositories() {
    local root=$1
    local target=${2:-}
    local repo_dir branch

    offline_mode_is_force && return
    ensure_git_for_offline_refresh "$target"
    command -v git >/dev/null 2>&1 || return
    curl -m 3 -sI https://github.com >/dev/null 2>&1 || return

    for repo_dir in "$root/repos/xworkspace-console" "$root/repos/playbooks"; do
        [ -d "$repo_dir/.git" ] || continue
        branch="$(git -C "$repo_dir" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
        [ -n "$branch" ] || continue
        info "Refreshing packaged $(basename "$repo_dir") checkout from origin/$branch..."
        if ! git -C "$repo_dir" fetch origin "$branch" >/dev/null 2>&1 ||
           ! git -C "$repo_dir" reset --hard "origin/$branch" >/dev/null 2>&1; then
            warn "Unable to refresh packaged $(basename "$repo_dir") checkout; using bundled revision."
        fi
    done
}

run_offline_installer() {
    local root=$1
    local target=$2
    local installer="$root/scripts/ai-workspace-offline-install.sh"
    local env_args=(
        "AI_WORKSPACE_OFFLINE_ACTIVE=true"
        "AI_WORKSPACE_DEPLOYMENT_LOCK_HELD=true"
        # The bundled repositories can retain the release builder's uid. Keep
        # this exception scoped to the offline installer process and children.
        "GIT_CONFIG_COUNT=1"
        "GIT_CONFIG_KEY_0=safe.directory"
        "GIT_CONFIG_VALUE_0=*"
    )
    local env_name

    [ -f "$installer" ] || return 1
    validate_offline_package_target "$root" "$target"
    refresh_offline_package_repositories "$root" "$target"
    chmod +x "$installer"

    for env_name in \
        AI_WORKSPACE_SECURITY_LEVEL \
        LITELLM_API_CADDY_STRICT_WHITELIST \
        LITELLM_CADDY_CONFIG_ENABLED \
        XWORKSPACE_CONSOLE_PUBLIC_ACCESS \
        XWORKMATE_BRIDGE_PUBLIC_ACCESS \
        XWORKMATE_BRIDGE_DOMAIN \
        GATEWAY_OPENCLAW_PUBLIC_ACCESS \
        VAULT_PUBLIC_ACCESS \
        XWORKSPACE_CONSOLE_ENABLE_XRDP \
        AI_WORKSPACE_RUNTIME_MODES \
        POSTGRESQL_DEPLOY_MODE \
        AI_WORKSPACE_AUTH_TOKEN \
        XWORKSPACE_CONSOLE_AUTH_TOKEN \
        XWORKMATE_BRIDGE_AUTH_TOKEN \
        BRIDGE_AUTH_TOKEN \
        INTERNAL_SERVICE_TOKEN \
        DEPLOY_TOKEN \
        ANSIBLE_VAULT_PASSWORD \
        AI_WORKSPACE_AUTH_TOKEN_FILE \
        AI_WORKSPACE_VAULT_PASSWORD_FILE \
        XWORKSPACE_CONSOLE_USER \
        XWORKSPACE_CONSOLE_HOME \
        XWORKSPACE_CONSOLE_SOURCE_REPO \
        XWORKSPACE_CONSOLE_SOURCE_VERSION \
        AI_WORKSPACE_APT_LOCK_TIMEOUT; do
        if [ -n "${!env_name+x}" ]; then
            env_args+=("$env_name=${!env_name}")
        fi
    done

    info "Using offline AI Workspace package at $root"
    if [ "$(id -u)" -eq 0 ]; then
        env "${env_args[@]}" bash "$installer"
    elif command -v sudo >/dev/null 2>&1; then
        sudo env "${env_args[@]}" bash "$installer"
    else
        return 1
    fi
}

try_bootstrap_from_offline_package() {
    if [ "${AI_WORKSPACE_OFFLINE_ACTIVE:-false}" = "true" ]; then
        return 1
    fi
    if offline_mode_is_off; then
        info "Offline package bootstrap disabled by AI_WORKSPACE_OFFLINE_MODE=$AI_WORKSPACE_OFFLINE_MODE"
        return 1
    fi
    if [ "$(detect_os)" != "linux" ]; then
        return 1
    fi

    local target filename source root
    target="$(detect_offline_target)" || {
        offline_fail_or_fallback "No supported offline package target detected for this host."
        return 1
    }
    filename="$(offline_package_filename "$target")"
    source="$(offline_package_source "$filename")"
    if [ -z "$source" ]; then
        offline_fail_or_fallback "No offline package source is configured."
        return 1
    fi

    root="$(prepare_offline_package_root "$source" "$filename")" || {
        offline_fail_or_fallback "Unable to prepare offline package from $source."
        return 1
    }
    if ! validate_offline_package_requirements "$root" "$target"; then
        offline_fail_or_fallback "Offline package requirements are incomplete for this host."
        return 1
    fi
    if run_offline_installer "$root" "$target"; then
        return 0
    fi

    error "Offline package installer failed after making deployment changes; online fallback was not started."
}

linux_default_console_user() {
    if [ -n "${XWORKSPACE_CONSOLE_USER:-}" ]; then
        printf '%s\n' "$XWORKSPACE_CONSOLE_USER"
    elif [ "$(id -u)" -eq 0 ]; then
        printf 'ubuntu\n'
    else
        id -un
    fi
}

linux_default_console_home() {
    local user=$1
    if [ -n "${XWORKSPACE_CONSOLE_HOME:-}" ]; then
        printf '%s\n' "$XWORKSPACE_CONSOLE_HOME"
    elif command -v getent >/dev/null 2>&1 && getent passwd "$user" >/dev/null 2>&1; then
        getent passwd "$user" | cut -d: -f6
    elif [ "$user" = "root" ]; then
        printf '/root\n'
    else
        printf '/home/%s\n' "$user"
    fi
}

append_linux_console_identity_vars() {
    local console_user=$1
    local console_home=$2

    ANSIBLE_EXTRA_VARS+=("-e" "xworkspace_console_user=$console_user")
    ANSIBLE_EXTRA_VARS+=("-e" "xworkspace_console_home=$console_home")
    ANSIBLE_EXTRA_VARS+=("-e" "xworkspace_console_root=$console_home/.local/state/ai-workspace")
    ANSIBLE_EXTRA_VARS+=("-e" "xworkspace_console_config_dir=$console_home/.config/xworkspace")
    ANSIBLE_EXTRA_VARS+=("-e" "xworkspace_console_scripts_dir=$console_home/.local/state/ai-workspace/scripts")
    ANSIBLE_EXTRA_VARS+=("-e" "xworkspace_console_repo_dir=$console_home/xworkspace-console")
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
        token="$(tr -d '\r\n' < "$AUTH_TOKEN_FILE")"
        if [ -n "$token" ]; then
            info "Found existing unified auth token at $AUTH_TOKEN_FILE, reusing it."
            printf '%s' "$token"
            return
        fi
        warn "Existing unified auth token file is empty; generating a replacement."
    fi

    info "No unified auth token provided. Generating a secure random token..."
    openssl rand -base64 32 | tr -d '\r\n' > "$AUTH_TOKEN_FILE"
    chmod 600 "$AUTH_TOKEN_FILE"
    info "Generated new unified auth token and saved to $AUTH_TOKEN_FILE"
    cat "$AUTH_TOKEN_FILE"
}

require_or_install_macos_cmds() {
    local missing=()
    for cmd in git node npm go curl lsof python3 ansible-playbook ttyd; do
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
            ansible-playbook) brew install ansible ;;
            ttyd) brew install ttyd ;;
            lsof) error "lsof is part of macOS; it is missing from PATH." ;;
        esac
    done
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
      "url": "http://localhost:${AI_WORKSPACE_LITELLM_PORT}/ui",
      "openMode": "iframe",
      "healthUrl": "http://127.0.0.1:${AI_WORKSPACE_LITELLM_PORT}/ui",
      "description": "Model routing and provider administration.",
      "icon": "chart",
      "match": ["litellm", "lite"],
      "port": ${AI_WORKSPACE_LITELLM_PORT},
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

# On macOS the vault role's "Ensure standalone Vault directories exist" task
# targets /etc/vault.d and /opt/vault/data with owner: root. Those paths are not
# writable under become=false and are non-standard for macOS, so patch the
# cloned role to: (1) skip that root-owned directory task on Darwin, (2) point
# the vault dirs/binary at Apple-standard, user-writable locations, and (3)
# create the data dir (user-owned) in the macОS task path. Linux is untouched.
patch_playbook_vault_macos() {
    local vars_file="roles/vhosts/vault/vars/main.yml"
    local tasks_file="roles/vhosts/vault/tasks/main.yml"
    local macos_file="roles/vhosts/vault/tasks/macos.yml"
    [ -f "$vars_file" ] && [ -f "$tasks_file" ] && [ -f "$macos_file" ] || return 0
    python3 - <<'PY'
from pathlib import Path

vars_path = Path("roles/vhosts/vault/vars/main.yml")
tasks_path = Path("roles/vhosts/vault/tasks/main.yml")
macos_path = Path("roles/vhosts/vault/tasks/macos.yml")

# 1) Make vault dirs and binary path OS-conditional (Linux unchanged).
vars_text = vars_path.read_text()
vars_subs = {
    "vault_binary_path: /usr/local/bin/vault":
        "vault_binary_path: \"{{ '/opt/homebrew/bin/vault' if ansible_os_family == 'Darwin' else '/usr/local/bin/vault' }}\"",
    "vault_config_dir: /etc/vault.d":
        "vault_config_dir: \"{{ (ansible_env.HOME ~ '/Library/Application Support/vault') if ansible_os_family == 'Darwin' else '/etc/vault.d' }}\"",
    "vault_data_dir: /opt/vault/data":
        "vault_data_dir: \"{{ (ansible_env.HOME ~ '/Library/Application Support/vault/data') if ansible_os_family == 'Darwin' else '/opt/vault/data' }}\"",
}
for old, new in vars_subs.items():
    if old in vars_text:
        vars_text = vars_text.replace(old, new)
vars_path.write_text(vars_text)

# 2) Skip the root-owned directory creation task on macOS.
tasks_text = tasks_path.read_text()
dir_when_old = (
    '  loop:\n'
    '    - "{{ vault_config_dir }}"\n'
    '    - "{{ vault_data_dir }}"\n'
    '  when:\n'
    '    - vault_deploy_mode == "standalone"\n'
)
dir_when_new = dir_when_old + "    - ansible_os_family != 'Darwin'\n"
if dir_when_old in tasks_text and "    - ansible_os_family != 'Darwin'\n\n- name: Deploy standalone Vault systemd" not in tasks_text:
    tasks_text = tasks_text.replace(dir_when_old, dir_when_new, 1)

# 2b) The admin bootstrap runs files/init_vault_admin.sh, which require_cmd's
# vault/jq/curl/base64. On macOS those live under Homebrew, which is not on the
# minimal PATH ansible.builtin.script uses; prepend the Homebrew bin dirs so the
# helper can find them.
boot_old = (
    '    --ui-url {{ vault_admin_ui_url | quote }}\n'
    '  no_log: true\n'
)
boot_new = (
    '    --ui-url {{ vault_admin_ui_url | quote }}\n'
    '  environment:\n'
    '    PATH: "/opt/homebrew/bin:/usr/local/bin:{{ ansible_env.PATH }}"\n'
    '  no_log: true\n'
)
if boot_old in tasks_text and boot_new not in tasks_text:
    tasks_text = tasks_text.replace(boot_old, boot_new, 1)

tasks_path.write_text(tasks_text)

# 2d) init_vault_admin.sh resolves the admin entity_id by logging in as the
# user. Once the login MFA enforcement it creates exists, that login is
# MFA-gated and returns no entity_id, so re-runs fail with "missing entityID".
# Resolve the entity via its userpass entity-alias instead (idempotent).
init_path = Path("roles/vhosts/vault/files/init_vault_admin.sh")
if init_path.exists():
    init_text = init_path.read_text()
    login_old = (
        'bootstrap_json="$(vault write -format=json "auth/userpass/login/${USERNAME}" password="$PASSWORD")"\n'
        'entity_id="$(printf \'%s\' "$bootstrap_json" | jq -r \'.auth.entity_id\')"\n'
        'bootstrap_token="$(printf \'%s\' "$bootstrap_json" | jq -r \'.auth.client_token\')"\n'
    )
    login_new = (
        'entity_id=""\n'
        '# bootstrap_token kept defined (empty) so any later "vault token revoke\n'
        '# $bootstrap_token" line stays valid under set -u; we no longer log in.\n'
        'bootstrap_token=""\n'
        'for alias_id in $(vault list -format=json identity/entity-alias/id 2>/dev/null | jq -r \'.[]?\'); do\n'
        '  alias_json="$(vault read -format=json "identity/entity-alias/id/${alias_id}" 2>/dev/null || true)"\n'
        '  alias_name="$(printf \'%s\' "$alias_json" | jq -r \'.data.name // empty\')"\n'
        '  alias_mount="$(printf \'%s\' "$alias_json" | jq -r \'.data.mount_accessor // empty\')"\n'
        '  if [[ "$alias_name" == "$USERNAME" && "$alias_mount" == "$userpass_accessor" ]]; then\n'
        '    entity_id="$(printf \'%s\' "$alias_json" | jq -r \'.data.canonical_id // empty\')"\n'
        '    break\n'
        '  fi\n'
        'done\n'
        '\n'
        'if [[ -z "$entity_id" ]]; then\n'
        '  entity_id="$(vault write -format=json identity/entity name="$USERNAME" policies="$POLICY_NAME" | jq -r \'.data.id\')"\n'
        '  vault write identity/entity-alias name="$USERNAME" canonical_id="$entity_id" mount_accessor="$userpass_accessor" >/dev/null\n'
        'fi\n'
    )
    if login_old in init_text:
        init_text = init_text.replace(login_old, login_new, 1)
        # Note: we intentionally do NOT delete the later "vault token revoke
        # $bootstrap_token" line — on some revisions it is wrapped in an if/fi,
        # and removing it would leave an empty then-block (syntax error). With
        # bootstrap_token="" set above, the revoke is a harmless no-op.
        init_path.write_text(init_text)

# 3) Create the macOS vault dirs (user-owned) before the launchd plist is laid down.
macos_text = macos_path.read_text()
dir_task = (
    "- name: Ensure macOS Vault directories exist\n"
    "  ansible.builtin.file:\n"
    "    path: \"{{ item }}\"\n"
    "    state: directory\n"
    "    mode: \"0755\"\n"
    "  loop:\n"
    "    - \"{{ vault_config_dir }}\"\n"
    "    - \"{{ vault_data_dir }}\"\n"
    "    - \"{{ ansible_env.HOME }}/.local/state/xworkspace\"\n\n"
)
anchor = "- name: Install HashiCorp Tap\n"
if "Ensure macOS Vault directories exist" not in macos_text and anchor in macos_text:
    macos_text = macos_text.replace(anchor, dir_task + anchor, 1)

# jq is not preinstalled on macOS and the Linux apt task that installs it is
# Darwin-skipped, yet init_vault_admin.sh requires it. Install it via Homebrew.
vault_brew_old = (
    "- name: Install Vault via Homebrew\n"
    "  ansible.builtin.command: brew install hashicorp/tap/vault\n"
    "  args:\n"
    "    creates: /opt/homebrew/bin/vault\n"
    "  changed_when: true\n"
)
jq_task = (
    "\n- name: Install jq via Homebrew (required by Vault admin bootstrap)\n"
    "  ansible.builtin.command: brew install jq\n"
    "  args:\n"
    "    creates: /opt/homebrew/bin/jq\n"
    "  changed_when: true\n"
)
if vault_brew_old in macos_text and "Install jq via Homebrew" not in macos_text:
    macos_text = macos_text.replace(vault_brew_old, vault_brew_old + jq_task, 1)
macos_path.write_text(macos_text)
PY
}

# The common role's "Base | *" tasks configure a Linux server: set timezone via
# timedatectl, rewrite /etc/hostname + /etc/hosts, set the hostname, harden ssh,
# configure fail2ban, raise file limits and open firewall ports. All of them run
# with become: true and target Linux-only tooling/paths, so they fail on macOS
# (e.g. timedatectl is absent). Patch the cloned role to skip the entire Base
# baseline on Darwin. Linux is untouched.
patch_playbook_common_macos() {
    local main_file="roles/vhosts/common/tasks/main.yml"
    [ -f "$main_file" ] || return 0
    python3 - <<'PY'
from pathlib import Path

path = Path("roles/vhosts/common/tasks/main.yml")
text = path.read_text()
guard = "  when: ansible_os_family != 'Darwin'\n"

# Tasks that end with a trailing attribute and have no `when:` yet -> append guard.
append_blocks = [
    ('- name: Base | set timezone\n'
     '  ansible.builtin.command: "timedatectl set-timezone Asia/Shanghai"\n'
     '  changed_when: false\n'
     '  become: true\n'),
    ('- name: Base | render /etc/hostname\n'
     '  ansible.builtin.template:\n'
     '    src: templates/hostname.j2\n'
     '    dest: /etc/hostname\n'
     '    owner: root\n'
     '    group: root\n'
     '    mode: "0644"\n'
     '  become: true\n'),
    ('- name: Base | set hostname\n'
     '  ansible.builtin.hostname:\n'
     '    name: "{{ inventory_hostname }}"\n'
     '  become: true\n'),
    ('- name: Base | update /etc/hosts\n'
     '  ansible.builtin.template:\n'
     '    src: templates/hosts\n'
     '    dest: /etc/hosts\n'
     '    owner: root\n'
     '    group: root\n'
     '    mode: "0644"\n'
     '  become: true\n'),
    ('- name: Base | harden ssh\n'
     '  ansible.builtin.script: files/secure_ssh.sh\n'
     '  become: true\n'),
    ('- name: Base | harden ssh config\n'
     '  ansible.builtin.import_tasks: harden_ssh.yml\n'
     '  tags: [ssh, security]\n'),
    ('- name: Base | configure fail2ban\n'
     '  ansible.builtin.import_tasks: fail2ban.yml\n'
     '  tags: [fail2ban, security]\n'),
]
for block in append_blocks:
    if block in text and (block + guard) not in text:
        text = text.replace(block, block + guard, 1)

# Tasks that already have a `when:` list -> add the Darwin condition to it.
when_blocks = [
    ('  when:\n'
     '    - common_security_limits.enabled | default(true) | bool\n'),
    ('  when:\n'
     '    - common_firewall.enabled | default(true) | bool\n'),
]
extra = "    - ansible_os_family != 'Darwin'\n"
for block in when_blocks:
    if block in text and (block + extra) not in text:
        text = text.replace(block, block + extra, 1)

path.write_text(text)
PY
}

# The postgres native (macOS) path installs postgresql@16 via the
# community.general.homebrew module, which auto-detects a brew prefix and can
# pick a stale Intel Homebrew at /usr/local that crashes on newer macOS versions
# ("unknown or unsupported macOS version"). Replace it with a brew command that
# runs the brew on PATH (Apple Silicon prefix first), matching vault/openclaw.
patch_playbook_postgres_macos() {
    local macos_file="roles/vhosts/postgres/tasks/macos.yml"
    [ -f "$macos_file" ] || return 0
    python3 - <<'PY'
from pathlib import Path

path = Path("roles/vhosts/postgres/tasks/macos.yml")
text = path.read_text()
old = (
    "- name: Ensure PostgreSQL 16 is installed via Homebrew\n"
    "  community.general.homebrew:\n"
    "    name: postgresql@16\n"
    "    state: present\n"
)
new = (
    "- name: Ensure PostgreSQL 16 is installed via Homebrew\n"
    "  ansible.builtin.command: brew install postgresql@16\n"
    "  environment:\n"
    "    PATH: \"/opt/homebrew/bin:/usr/local/bin:{{ ansible_env.PATH }}\"\n"
    "    HOMEBREW_NO_AUTO_UPDATE: \"1\"\n"
    "  register: postgresql_brew_install\n"
    "  changed_when: >-\n"
    "    'already installed' not in (postgresql_brew_install.stderr | default(''))\n"
    "    and 'already installed' not in (postgresql_brew_install.stdout | default(''))\n"
    "  failed_when: postgresql_brew_install.rc != 0\n"
)
if old in text:
    text = text.replace(old, new, 1)
    path.write_text(text)
PY
}

# litellm installs python@3.13 via the community.general.homebrew module on
# macOS, which has the same stale-Intel-Homebrew crash risk. Replace it with a
# brew command using the PATH brew (Apple Silicon prefix first).
patch_playbook_litellm_macos() {
    local main_file="roles/vhosts/litellm/tasks/main.yml"
    [ -f "$main_file" ] || return 0
    python3 - <<'PY'
from pathlib import Path

path = Path("roles/vhosts/litellm/tasks/main.yml")
text = path.read_text()
old = (
    "- name: Install LiteLLM prerequisites (macOS)\n"
    "  community.general.homebrew:\n"
    "    name: python@3.13\n"
    "    state: present\n"
    "  when: ansible_os_family == 'Darwin'\n"
)
new = (
    "- name: Install LiteLLM prerequisites (macOS)\n"
    "  ansible.builtin.command: brew install python@3.13\n"
    "  environment:\n"
    "    PATH: \"/opt/homebrew/bin:/usr/local/bin:{{ ansible_env.PATH }}\"\n"
    "    HOMEBREW_NO_AUTO_UPDATE: \"1\"\n"
    "  register: litellm_brew_python\n"
    "  changed_when: >-\n"
    "    'already installed' not in (litellm_brew_python.stderr | default(''))\n"
    "    and 'already installed' not in (litellm_brew_python.stdout | default(''))\n"
    "  failed_when: litellm_brew_python.rc != 0\n"
    "  when: ansible_os_family == 'Darwin'\n"
)
if old in text:
    text = text.replace(old, new, 1)

# The config dir and env-file tasks hardcode owner/group root, which cannot be
# chowned under become=false on macOS. Make ownership OS-conditional (service
# user/group on Darwin, root on Linux). The config dir path itself is relocated
# to a user-writable location via the litellm_config_dir extra-var.
owner_subs = [
    (
        '    path: "{{ litellm_config_dir }}"\n'
        '    state: directory\n'
        '    owner: root\n'
        '    group: root\n'
        '    mode: "0755"\n',
        '    path: "{{ litellm_config_dir }}"\n'
        '    state: directory\n'
        '    owner: "{{ litellm_service_user if ansible_os_family == \'Darwin\' else \'root\' }}"\n'
        '    group: "{{ litellm_service_group if ansible_os_family == \'Darwin\' else \'root\' }}"\n'
        '    mode: "0755"\n',
    ),
    (
        '    dest: "{{ litellm_env_file }}"\n'
        '    owner: root\n'
        '    group: root\n'
        '    mode: "0600"\n',
        '    dest: "{{ litellm_env_file }}"\n'
        '    owner: "{{ litellm_service_user if ansible_os_family == \'Darwin\' else \'root\' }}"\n'
        '    group: "{{ litellm_service_group if ansible_os_family == \'Darwin\' else \'root\' }}"\n'
        '    mode: "0600"\n',
    ),
]
for o, n in owner_subs:
    if o in text:
        text = text.replace(o, n, 1)

path.write_text(text)

# provision-database.yml runs psql with become_user postgres, which has no
# equivalent on macOS Homebrew (no postgres system user, no passwordless sudo,
# psql off-PATH). On Darwin run without escalation as the current user (the brew
# DB superuser) and put the postgresql@16 bin on PATH. Linux unchanged.
prov_path = Path("roles/vhosts/litellm/tasks/provision-database.yml")
if prov_path.exists():
    prov = prov_path.read_text()
    prov_old = (
        "  args:\n"
        "    executable: /bin/bash\n"
        "  become: true\n"
        "  become_user: \"{{ 'root' if litellm_database_provisioner == 'docker' else 'postgres' }}\"\n"
    )
    prov_new = (
        "  args:\n"
        "    executable: /bin/bash\n"
        "  environment:\n"
        "    PATH: \"/opt/homebrew/opt/postgresql@16/bin:/usr/local/opt/postgresql@16/bin:{{ ansible_env.PATH }}\"\n"
        "  become: \"{{ ansible_os_family != 'Darwin' }}\"\n"
        "  become_user: \"{{ 'root' if litellm_database_provisioner == 'docker' else 'postgres' }}\"\n"
    )
    if prov_old in prov:
        prov = prov.replace(prov_old, prov_new)
        prov_path.write_text(prov)
PY
}

# The remote setup-xworkspace-console playbook downloads a prebuilt runtime
# archive for Linux, but no Darwin release archives are built. On Darwin, skip
# downloading/unpacking and instead clone the git repository and build from source.
patch_playbook_console_macos() {
    local main_file="setup-xworkspace-console.yaml"
    local macos_file="xworkspace_console_macos.yml"
    [ -f "$main_file" ] || return 0
    python3 - <<'PY'
from pathlib import Path

path = Path("setup-xworkspace-console.yaml")
if path.exists():
    text = path.read_text()

    # 1. Skip release archive download/validate/install tasks on macOS.
    download_old = (
        "    - name: Download XWorkspace Console runtime release\n"
        "      ansible.builtin.get_url:\n"
        "        url: \"https://github.com/ai-workspace-lab/xworkspace-console/releases/latest/download/xworkspace-console-runtime-{{ ansible_system | lower }}-{{ 'amd64' if ansible_architecture in ['x86_64', 'amd64'] else 'arm64' }}.tar.gz\"\n"
        "        dest: \"/tmp/xworkspace-console-runtime.tar.gz\"\n"
        "        mode: \"0644\"\n"
        "        force: true\n"
        "      when: xworkspace_console_runtime_archive | length == 0"
    )
    download_new = (
        "    - name: Download XWorkspace Console runtime release\n"
        "      ansible.builtin.get_url:\n"
        "        url: \"https://github.com/ai-workspace-lab/xworkspace-console/releases/latest/download/xworkspace-console-runtime-{{ ansible_system | lower }}-{{ 'amd64' if ansible_architecture in ['x86_64', 'amd64'] else 'arm64' }}.tar.gz\"\n"
        "        dest: \"/tmp/xworkspace-console-runtime.tar.gz\"\n"
        "        mode: \"0644\"\n"
        "        force: true\n"
        "      when:\n"
        "        - xworkspace_console_runtime_archive | length == 0\n"
        "        - ansible_os_family != 'Darwin'"
    )
    if download_old in text:
        text = text.replace(download_old, download_new, 1)

    validate_old = (
        "    - name: Validate packaged XWorkspace Console runtime\n"
        "      ansible.builtin.stat:\n"
        "        path: \"{{ xworkspace_console_runtime_archive_resolved }}\"\n"
        "      register: xworkspace_console_runtime_archive_stat"
    )
    validate_new = (
        "    - name: Validate packaged XWorkspace Console runtime\n"
        "      ansible.builtin.stat:\n"
        "        path: \"{{ xworkspace_console_runtime_archive_resolved }}\"\n"
        "      register: xworkspace_console_runtime_archive_stat\n"
        "      when: ansible_os_family != 'Darwin'"
    )
    if validate_old in text and (validate_old + "\n      when:") not in text:
        text = text.replace(validate_old, validate_new, 1)

    require_old = (
        "    - name: Require packaged XWorkspace Console runtime\n"
        "      ansible.builtin.assert:\n"
        "        that:\n"
        "          - xworkspace_console_runtime_archive_stat.stat.exists | default(false)\n"
        "        fail_msg: \"A valid XWORKSPACE_CONSOLE_RUNTIME_ARCHIVE is required or download failed.\""
    )
    require_new = (
        "    - name: Require packaged XWorkspace Console runtime\n"
        "      ansible.builtin.assert:\n"
        "        that:\n"
        "          - xworkspace_console_runtime_archive_stat.stat.exists | default(false)\n"
        "        fail_msg: \"A valid XWORKSPACE_CONSOLE_RUNTIME_ARCHIVE is required or download failed.\"\n"
        "      when: ansible_os_family != 'Darwin'"
    )
    if require_old in text and (require_old + "\n      when:") not in text:
        text = text.replace(require_old, require_new, 1)

    marker_old = (
        "    - name: Inspect installed XWorkspace Console runtime marker\n"
        "      ansible.builtin.slurp:\n"
        "        path: \"{{ xworkspace_console_runtime_marker }}\"\n"
        "      register: xworkspace_console_runtime_marker_content\n"
        "      failed_when: false"
    )
    marker_new = (
        "    - name: Inspect installed XWorkspace Console runtime marker\n"
        "      ansible.builtin.slurp:\n"
        "        path: \"{{ xworkspace_console_runtime_marker }}\"\n"
        "      register: xworkspace_console_runtime_marker_content\n"
        "      failed_when: false\n"
        "      when: ansible_os_family != 'Darwin'"
    )
    if marker_old in text and (marker_old + "\n      when:") not in text:
        text = text.replace(marker_old, marker_new, 1)

    install_old = (
        "    - name: Install packaged XWorkspace Console runtime\n"
        "      ansible.builtin.unarchive:\n"
        "        src: \"{{ xworkspace_console_runtime_archive_resolved }}\"\n"
        "        dest: \"{{ xworkspace_console_repo_dir | dirname }}\"\n"
        "        remote_src: true\n"
        "        owner: \"{{ xworkspace_console_user }}\"\n"
        "        group: \"{{ 'staff' if ansible_os_family == 'Darwin' else xworkspace_console_user }}\"\n"
        "      when:\n"
        "        - xworkspace_console_runtime_archive_stat.stat.exists | default(false)\n"
        "        - >-\n"
        "          (xworkspace_console_runtime_marker_content.content | default('') | b64decode | trim)\n"
        "          != (xworkspace_console_runtime_archive_stat.stat.checksum | default(''))\n"
        "          or not (xworkspace_console_api_binary is file)\n"
        "          or not ((xworkspace_console_dashboard_dir ~ '/dist/index.html') is file)"
    )
    install_new = (
        "    - name: Install packaged XWorkspace Console runtime\n"
        "      ansible.builtin.unarchive:\n"
        "        src: \"{{ xworkspace_console_runtime_archive_resolved }}\"\n"
        "        dest: \"{{ xworkspace_console_repo_dir | dirname }}\"\n"
        "        remote_src: true\n"
        "        owner: \"{{ xworkspace_console_user }}\"\n"
        "        group: \"{{ 'staff' if ansible_os_family == 'Darwin' else xworkspace_console_user }}\"\n"
        "      when:\n"
        "        - ansible_os_family != 'Darwin'\n"
        "        - xworkspace_console_runtime_archive_stat.stat.exists | default(false)\n"
        "        - >-\n"
        "          (xworkspace_console_runtime_marker_content.content | default('') | b64decode | trim)\n"
        "          != (xworkspace_console_runtime_archive_stat.stat.checksum | default(''))\n"
        "          or not (xworkspace_console_api_binary is file)\n"
        "          or not ((xworkspace_console_dashboard_dir ~ '/dist/index.html') is file)"
    )
    if install_old in text:
        text = text.replace(install_old, install_new, 1)

    record_old = (
        "    - name: Record installed XWorkspace Console runtime checksum\n"
        "      ansible.builtin.copy:\n"
        "        dest: \"{{ xworkspace_console_runtime_marker }}\"\n"
        "        owner: \"{{ xworkspace_console_user }}\"\n"
        "        group: \"{{ 'staff' if ansible_os_family == 'Darwin' else xworkspace_console_user }}\"\n"
        "        mode: \"0644\"\n"
        "        content: \"{{ xworkspace_console_runtime_archive_stat.stat.checksum }}\\n\"\n"
        "      when:\n"
        "        - xworkspace_console_runtime_archive_stat.stat.exists | default(false)"
    )
    record_new = (
        "    - name: Record installed XWorkspace Console runtime checksum\n"
        "      ansible.builtin.copy:\n"
        "        dest: \"{{ xworkspace_console_runtime_marker }}\"\n"
        "        owner: \"{{ xworkspace_console_user }}\"\n"
        "        group: \"{{ 'staff' if ansible_os_family == 'Darwin' else xworkspace_console_user }}\"\n"
        "        mode: \"0644\"\n"
        "        content: \"{{ xworkspace_console_runtime_archive_stat.stat.checksum }}\\n\"\n"
        "      when:\n"
        "        - ansible_os_family != 'Darwin'\n"
        "        - xworkspace_console_runtime_archive_stat.stat.exists | default(false)"
    )
    if record_old in text:
        text = text.replace(record_old, record_new, 1)

    # 2. Inject Clone and Build tasks on macOS (Darwin).
    anchor = "    - name: Deploy AI Workspace portal service configuration"
    injected_tasks = (
        "    - name: Check if xworkspace-console repo already exists (macOS)\n"
        "      ansible.builtin.stat:\n"
        "        path: \"{{ xworkspace_console_repo_dir }}/.git\"\n"
        "      register: xworkspace_console_git_stat_macos\n"
        "      when: ansible_os_family == 'Darwin'\n"
        "\n"
        "    - name: Clone xworkspace-console repository (macOS)\n"
        "      ansible.builtin.git:\n"
        "        repo: \"{{ xworkspace_console_source_repo }}\"\n"
        "        dest: \"{{ xworkspace_console_repo_dir }}\"\n"
        "        version: \"{{ xworkspace_console_source_version }}\"\n"
        "        depth: 1\n"
        "      become_user: \"{{ xworkspace_console_user }}\"\n"
        "      when:\n"
        "        - ansible_os_family == 'Darwin'\n"
        "        - not (xworkspace_console_git_stat_macos.stat.exists | default(false))\n"
        "\n"
        "    - name: Build dashboard assets on target (macOS)\n"
        "      ansible.builtin.shell: |\n"
        "        set -euo pipefail\n"
        "        cd \"{{ xworkspace_console_dashboard_dir }}\"\n"
        "        source_commit=\"$(git -C \"{{ xworkspace_console_repo_dir }}\" rev-parse HEAD)\"\n"
        "        marker=\".ai-workspace-build-commit\"\n"
        "        if [ -f \"dist/index.html\" ] && [ \"$(cat \"$marker\" 2>/dev/null || true)\" = \"$source_commit\" ]; then\n"
        "          echo \"build=unchanged\"\n"
        "          exit 0\n"
        "        fi\n"
        "        npm install && npm run build\n"
        "        printf '%s\\n' \"$source_commit\" > \"$marker\"\n"
        "        echo \"build=changed\"\n"
      "      args:\n"
        "        executable: /bin/bash\n"
        "      become_user: \"{{ xworkspace_console_user }}\"\n"
        "      register: xworkspace_console_dashboard_build_macos\n"
        "      changed_when: \"'build=changed' in (xworkspace_console_dashboard_build_macos.stdout | default(''))\"\n"
        "      when: ansible_os_family == 'Darwin'\n"
        "\n"
    )
    if anchor in text and "Clone xworkspace-console repository (macOS)" not in text:
        text = text.replace(anchor, injected_tasks + anchor, 1)

    path.write_text(text)

# Patch xworkspace_console_macos.yml to ensure LaunchAgents directory exists
macos_path = Path("xworkspace_console_macos.yml")
if macos_path.exists():
    macos_text = macos_path.read_text()
    launchagents_task = (
        "- name: Ensure macOS LaunchAgents directory exists\n"
        "  ansible.builtin.file:\n"
        "    path: \"{{ ansible_env.HOME }}/Library/LaunchAgents\"\n"
        "    state: directory\n"
        "    mode: \"0755\"\n\n"
    )
    if "Ensure macOS LaunchAgents directory exists" not in macos_text:
        if macos_text.startswith("---\n"):
            macos_text = "---\n" + launchagents_task + macos_text[4:]
        else:
            macos_text = launchagents_task + macos_text
        macos_path.write_text(macos_text)
PY
}

patch_playbook_openclaw_macos() {
    local main_file="roles/vhosts/gateway_openclaw/tasks/main.yml"
    [ -f "$main_file" ] || return 0
    python3 - <<'PY'
from pathlib import Path

path = Path("roles/vhosts/gateway_openclaw/tasks/main.yml")
if path.exists():
    text = path.read_text()
    
    download_old = (
        "- name: Download OpenClaw Multi-Session Plugins offline archive\n"
        "  ansible.builtin.get_url:\n"
        "    url: \"{{ gateway_openclaw_multi_session_plugin_archive_url }}\"\n"
        "    dest: \"/tmp/openclaw-multi-session-plugins.tar.gz\"\n"
        "    mode: \"0644\""
    )
    download_new = (
        "- name: Download OpenClaw Multi-Session Plugins offline archive\n"
        "  ansible.builtin.get_url:\n"
        "    url: \"{{ gateway_openclaw_multi_session_plugin_archive_url }}\"\n"
        "    dest: \"/tmp/openclaw-multi-session-plugins.tar.gz\"\n"
        "    mode: \"0644\"\n"
        "  when: ansible_os_family != 'Darwin'"
    )
    if download_old in text:
        text = text.replace(download_old, download_new, 1)

    extract_old = (
        "- name: Extract OpenClaw Multi-Session Plugins\n"
        "  ansible.builtin.unarchive:\n"
        "    src: \"/tmp/openclaw-multi-session-plugins.tar.gz\"\n"
        "    dest: \"{{ gateway_openclaw_home }}/.openclaw/extensions\"\n"
        "    remote_src: true\n"
        "    owner: \"{{ gateway_openclaw_service_user }}\"\n"
        "    group: \"{{ gateway_openclaw_service_group }}\"\n"
        "    mode: \"0755\"\n"
        "  become: \"{{ ansible_os_family != 'Darwin' }}\"\n"
        "  notify: Restart openclaw gateway"
    )
    extract_new = (
        "- name: Extract OpenClaw Multi-Session Plugins\n"
        "  ansible.builtin.unarchive:\n"
        "    src: \"/tmp/openclaw-multi-session-plugins.tar.gz\"\n"
        "    dest: \"{{ gateway_openclaw_home }}/.openclaw/extensions\"\n"
        "    remote_src: true\n"
        "    owner: \"{{ gateway_openclaw_service_user }}\"\n"
        "    group: \"{{ gateway_openclaw_service_group }}\"\n"
        "    mode: \"0755\"\n"
        "  become: \"{{ ansible_os_family != 'Darwin' }}\"\n"
        "  notify: Restart openclaw gateway\n"
        "  when: ansible_os_family != 'Darwin'"
    )
    if extract_old in text:
        text = text.replace(extract_old, extract_new, 1)

    anchor = "- name: Ensure OpenClaw global plugin npm directory exists"
    injected = (
        "- name: Check if openclaw-multi-session-plugins repo exists (macOS)\n"
        "  ansible.builtin.stat:\n"
        "    path: \"{{ gateway_openclaw_multi_session_plugin_dir | default('/tmp/openclaw-multi-session-plugins') }}/.git\"\n"
        "  register: openclaw_plugin_git_stat_macos\n"
        "  when: ansible_os_family == 'Darwin'\n"
        "\n"
        "- name: Clone openclaw-multi-session-plugins repository (macOS)\n"
        "  ansible.builtin.git:\n"
        "    repo: \"https://github.com/ai-workspace-lab/openclaw-multi-session-plugins.git\"\n"
        "    dest: \"{{ gateway_openclaw_multi_session_plugin_dir | default('/tmp/openclaw-multi-session-plugins') }}\"\n"
        "    version: main\n"
        "    depth: 1\n"
        "  become_user: \"{{ gateway_openclaw_service_user }}\"\n"
        "  when:\n"
        "    - ansible_os_family == 'Darwin'\n"
        "    - not (openclaw_plugin_git_stat_macos.stat.exists | default(false))\n"
        "\n"
        "- name: Build openclaw-multi-session-plugins (macOS)\n"
        "  ansible.builtin.shell: |\n"
        "    set -euo pipefail\n"
        "    cd \"{{ gateway_openclaw_multi_session_plugin_dir | default('/tmp/openclaw-multi-session-plugins') }}\"\n"
        "    npm install && npm run build\n"
        "  args:\n"
        "    executable: /bin/bash\n"
        "  become_user: \"{{ gateway_openclaw_service_user }}\"\n"
        "  when: ansible_os_family == 'Darwin'\n"
        "\n"
        "- name: Link openclaw-multi-session-plugins to extensions (macOS)\n"
        "  ansible.builtin.file:\n"
        "    src: \"{{ gateway_openclaw_multi_session_plugin_dir | default('/tmp/openclaw-multi-session-plugins') }}\"\n"
        "    dest: \"{{ gateway_openclaw_home }}/.openclaw/extensions/openclaw-multi-session-plugins\"\n"
        "    state: link\n"
        "    owner: \"{{ gateway_openclaw_service_user }}\"\n"
        "    group: \"{{ gateway_openclaw_service_group }}\"\n"
        "  become_user: \"{{ gateway_openclaw_service_user }}\"\n"
        "  when: ansible_os_family == 'Darwin'\n"
        "  notify: Restart openclaw gateway\n"
        "\n"
    )
    if anchor in text and "Clone openclaw-multi-session-plugins repository (macOS)" not in text:
        text = text.replace(anchor, injected + anchor, 1)

    path.write_text(text)
PY
}

ensure_core_skills_source() {
    if [ "${AI_WORKSPACE_PREFETCH_COMPLETED:-false}" = "true" ] &&
       [ -d "$XWORKSPACE_CORE_SKILLS_DIR/skills" ]; then
        info "Using prefetched xworkspace-core-skills directory at $XWORKSPACE_CORE_SKILLS_DIR"
    elif [ "${AI_WORKSPACE_OFFLINE_ACTIVE:-false}" = "true" ] &&
       [ -d "$XWORKSPACE_CORE_SKILLS_DIR/skills" ]; then
        info "Using packaged xworkspace-core-skills directory at $XWORKSPACE_CORE_SKILLS_DIR"
    elif [ -d "$XWORKSPACE_CORE_SKILLS_DIR/.git" ]; then
        info "Updating xworkspace-core-skills checkout at $XWORKSPACE_CORE_SKILLS_DIR..."
        git -C "$XWORKSPACE_CORE_SKILLS_DIR" fetch origin
        git -C "$XWORKSPACE_CORE_SKILLS_DIR" reset --hard origin/main
    elif [ -d "$XWORKSPACE_CORE_SKILLS_DIR/skills" ]; then
        info "Using existing xworkspace-core-skills directory at $XWORKSPACE_CORE_SKILLS_DIR"
    else
        info "Cloning xworkspace-core-skills to $XWORKSPACE_CORE_SKILLS_DIR..."
        rm -rf "$XWORKSPACE_CORE_SKILLS_DIR"
        git clone "$XWORKSPACE_CORE_SKILLS_REPO_URL" "$XWORKSPACE_CORE_SKILLS_DIR"
    fi

    [ -d "$XWORKSPACE_CORE_SKILLS_DIR/skills" ] || error "xworkspace core skills source missing: $XWORKSPACE_CORE_SKILLS_DIR/skills"
}

ensure_xworkmate_bridge_source() {
    if [ "${AI_WORKSPACE_PREFETCH_COMPLETED:-false}" = "true" ] &&
       [ -f "$XWORKMATE_BRIDGE_SOURCE_DIR/go.mod" ]; then
        info "Using prefetched xworkmate-bridge source at $XWORKMATE_BRIDGE_SOURCE_DIR"
    elif [ "${AI_WORKSPACE_OFFLINE_ACTIVE:-false}" = "true" ] &&
       [ -f "$XWORKMATE_BRIDGE_SOURCE_DIR/go.mod" ]; then
        info "Using packaged xworkmate-bridge source at $XWORKMATE_BRIDGE_SOURCE_DIR"
    elif [ -d "$XWORKMATE_BRIDGE_SOURCE_DIR/.git" ]; then
        info "Updating xworkmate-bridge checkout at $XWORKMATE_BRIDGE_SOURCE_DIR..."
        git -C "$XWORKMATE_BRIDGE_SOURCE_DIR" fetch origin
        git -C "$XWORKMATE_BRIDGE_SOURCE_DIR" checkout "$XWORKMATE_BRIDGE_BRANCH"
        git -C "$XWORKMATE_BRIDGE_SOURCE_DIR" reset --hard "origin/$XWORKMATE_BRIDGE_BRANCH"
    elif [ -f "$XWORKMATE_BRIDGE_SOURCE_DIR/go.mod" ]; then
        info "Using existing xworkmate-bridge source at $XWORKMATE_BRIDGE_SOURCE_DIR"
    else
        info "Cloning xworkmate-bridge to $XWORKMATE_BRIDGE_SOURCE_DIR..."
        rm -rf "$XWORKMATE_BRIDGE_SOURCE_DIR"
        git clone -b "$XWORKMATE_BRIDGE_BRANCH" "$XWORKMATE_BRIDGE_REPO_URL" "$XWORKMATE_BRIDGE_SOURCE_DIR"
    fi

    [ -f "$XWORKMATE_BRIDGE_SOURCE_DIR/go.mod" ] || error "xworkmate-bridge source missing: $XWORKMATE_BRIDGE_SOURCE_DIR/go.mod"
}

read_playbook_default() {
    local file=$1
    local key=$2
    sed -n "s/^${key}:[[:space:]]*[\"']\\{0,1\\}\\([^\"']*\\)[\"']\\{0,1\\}[[:space:]]*$/\\1/p" "$file" | head -n 1
}

prefetch_git_repository() {
    local label=$1
    local repo=$2
    local ref=$3
    local dest=$4

    if [ -d "$dest/.git" ]; then
        git -C "$dest" remote set-url origin "$repo"
        git -C "$dest" fetch --force --prune origin "$ref"
    else
        rm -rf "$dest"
        mkdir -p "$(dirname "$dest")"
        git clone --no-checkout "$repo" "$dest"
        git -C "$dest" fetch --force origin "$ref"
    fi
    # Point a local branch at the fetched commit instead of leaving a detached
    # HEAD. The prefetch dir is later consumed via `git clone file://<dest>`,
    # which only transfers objects reachable from branches/tags (a detached HEAD
    # or remote-tracking ref is not enough) — otherwise the downstream checkout
    # of this exact commit fails with "fatal: unable to read tree <sha>".
    git -C "$dest" checkout --force -B ai-workspace-prefetched FETCH_HEAD
    git -C "$dest" clean -ffd
    printf '%s\n' "$(git -C "$dest" rev-parse HEAD)" > "$dest/.ai-workspace-prefetched-commit"
    info "Prefetched $label at $(cat "$dest/.ai-workspace-prefetched-commit")"
}

prefetch_postgres_image() {
    local image=$1
    docker pull "$image"
}

prefetch_independent_sources() {
    if [ "$AI_WORKSPACE_PREFETCH_ENABLED" != "true" ]; then
        info "Phase 2 prefetch disabled by AI_WORKSPACE_PREFETCH_ENABLED."
        return
    fi
    if [ "${AI_WORKSPACE_OFFLINE_ACTIVE:-false}" = "true" ]; then
        info "Offline package is active; skipping online Phase 2 prefetch."
        return
    fi
    if [ "$(detect_os)" != "linux" ]; then
        return
    fi
    validate_parallel_job_limit

    local console_dir="$AI_WORKSPACE_PREFETCH_DIR/xworkspace-console"
    local qmd_dir="$AI_WORKSPACE_PREFETCH_DIR/qmd"
    local litellm_dir="$AI_WORKSPACE_PREFETCH_DIR/litellm"
    local qmd_repo qmd_ref litellm_repo litellm_ref postgres_image
    qmd_repo="${QMD_SOURCE_REPO:-$(read_playbook_default roles/vhosts/qmd/defaults/main.yml qmd_source_repo)}"
    qmd_ref="${QMD_VERSION:-$(read_playbook_default roles/vhosts/qmd/defaults/main.yml qmd_version)}"
    litellm_repo="${LITELLM_SOURCE_REPO:-$(read_playbook_default roles/vhosts/litellm/defaults/main.yml litellm_source_repo)}"
    litellm_ref="${LITELLM_VERSION:-$(read_playbook_default roles/vhosts/litellm/defaults/main.yml litellm_version)}"
    postgres_image="${POSTGRESQL_IMAGE:-$(read_playbook_default roles/vhosts/postgres/defaults/main.yml postgresql_image)}"
    [ -n "$qmd_repo" ] && [ -n "$qmd_ref" ] || error "Unable to resolve pinned QMD source."
    [ -n "$litellm_repo" ] && [ -n "$litellm_ref" ] || error "Unable to resolve pinned LiteLLM source."

    info "Starting load-adaptive Phase 2 source prefetch (current limit $(dynamic_parallel_job_limit), hard limit $(( $(online_cpu_count) * 2 )))..."
    reset_bounded_jobs
    run_bounded "repo:console" prefetch_git_repository \
        "xworkspace-console" "$XWORKSPACE_CONSOLE_REPO_URL" "${XWORKSPACE_CONSOLE_SOURCE_VERSION:-main}" "$console_dir"
    run_bounded "repo:core-skills" prefetch_git_repository \
        "xworkspace-core-skills" "$XWORKSPACE_CORE_SKILLS_REPO_URL" "main" "$XWORKSPACE_CORE_SKILLS_DIR"
    run_bounded "repo:bridge" prefetch_git_repository \
        "xworkmate-bridge" "$XWORKMATE_BRIDGE_REPO_URL" "$XWORKMATE_BRIDGE_BRANCH" "$XWORKMATE_BRIDGE_SOURCE_DIR"
    run_bounded "repo:qmd" prefetch_git_repository \
        "qmd" "$qmd_repo" "$qmd_ref" "$qmd_dir"
    run_bounded "repo:litellm" prefetch_git_repository \
        "litellm" "$litellm_repo" "$litellm_ref" "$litellm_dir"

    if command -v docker >/dev/null 2>&1 &&
       printf ',%s,' "${AI_WORKSPACE_RUNTIME_MODES:-docker,systemd}" | grep -q ',docker,'; then
        [ -n "$postgres_image" ] || error "Unable to resolve pinned PostgreSQL image."
        run_bounded "image:postgres" prefetch_postgres_image "$postgres_image"
    fi
    if ! wait_for_bounded_jobs; then
        warn "Phase 2 source prefetch failed; continuing with the standard Ansible source tasks."
        return
    fi

    export XWORKSPACE_CONSOLE_SOURCE_REPO="file://$console_dir"
    export XWORKSPACE_CONSOLE_SOURCE_VERSION
    XWORKSPACE_CONSOLE_SOURCE_VERSION="$(cat "$console_dir/.ai-workspace-prefetched-commit")"
    export QMD_SOURCE_REPO="file://$qmd_dir"
    export QMD_VERSION="$qmd_ref"
    export LITELLM_SOURCE_REPO="file://$litellm_dir"
    export LITELLM_VERSION="$litellm_ref"
    export AI_WORKSPACE_PREFETCH_COMPLETED=true
    success "Phase 2 source prefetch completed."
}

ensure_runtime_build_user() {
    local user=$1
    local home=$2

    if id "$user" >/dev/null 2>&1; then
        return
    fi
    if [ "$(id -u)" -ne 0 ]; then
        warn "Cannot create runtime build user $user without root privileges."
        return 1
    fi
    getent group "$user" >/dev/null 2>&1 || groupadd "$user"
    useradd --create-home --home-dir "$home" --gid "$user" --shell /bin/bash "$user"
}

run_as_runtime_user() {
    local user=$1
    local home=$2
    shift 2

    if [ "$(id -u)" -eq 0 ]; then
        runuser -u "$user" -- env HOME="$home" "$@"
    else
        env HOME="$home" "$@"
    fi
}

prepare_runtime_checkout() {
    local user=$1
    local home=$2
    local repo=$3
    local ref=$4
    local dest=$5

    if [ -d "$dest/.git" ]; then
        run_as_runtime_user "$user" "$home" git -C "$dest" remote set-url origin "$repo"
        run_as_runtime_user "$user" "$home" git -C "$dest" fetch --force --prune origin "$ref"
    else
        rm -rf "$dest"
        install -d -o "$user" -g "$user" "$(dirname "$dest")"
        run_as_runtime_user "$user" "$home" git clone --no-checkout "$repo" "$dest"
        run_as_runtime_user "$user" "$home" git -C "$dest" fetch --force origin "$ref"
    fi
    run_as_runtime_user "$user" "$home" git -C "$dest" checkout --force --detach FETCH_HEAD
    run_as_runtime_user "$user" "$home" git -C "$dest" clean -ffd
}

prebuild_console_dashboard() {
    local user=$1
    local home=$2
    local repo=$3
    local ref=$4
    local dest=$5
    local cache_dir=$6

    prepare_runtime_checkout "$user" "$home" "$repo" "$ref" "$dest"
    install -d -o "$user" -g "$user" "$cache_dir"
    run_as_runtime_user "$user" "$home" env npm_config_cache="$cache_dir" \
        npm install --no-audit --no-fund --prefix "$dest/dashboard"
    run_as_runtime_user "$user" "$home" env npm_config_cache="$cache_dir" \
        npm run build --prefix "$dest/dashboard"
    run_as_runtime_user "$user" "$home" git -C "$dest" rev-parse HEAD \
        > "$dest/dashboard/.ai-workspace-build-commit"
}

prebuild_qmd_runtime() {
    local user=$1
    local home=$2
    local repo=$3
    local ref=$4
    local dest=$5
    local cache_dir=$6

    prepare_runtime_checkout "$user" "$home" "$repo" "$ref" "$dest"
    install -d -o "$user" -g "$user" "$cache_dir" "$home/.bun/bin"
    run_as_runtime_user "$user" "$home" env npm_config_cache="$cache_dir" \
        npm install --no-audit --no-fund --prefix "$dest"
    run_as_runtime_user "$user" "$home" env npm_config_cache="$cache_dir" \
        npm run build --prefix "$dest"
    run_as_runtime_user "$user" "$home" ln -sfn "$dest/bin/qmd" "$home/.bun/bin/qmd"
}

preinstall_openclaw_runtime() {
    local user=$1
    local home=$2
    local version=$3
    local cache_dir=$4

    install -d -o "$user" -g "$user" "$cache_dir" "$home/.local"
    run_as_runtime_user "$user" "$home" env npm_config_cache="$cache_dir" \
        npm install --global --omit=dev --no-audit --no-fund \
        --prefix "$home/.local" "openclaw@$version"
}

prebuild_independent_runtimes() {
    if [ "$AI_WORKSPACE_RUNTIME_PREBUILD_ENABLED" != "true" ]; then
        info "Runtime prebuild disabled by AI_WORKSPACE_RUNTIME_PREBUILD_ENABLED."
        return
    fi
    if ! command -v npm >/dev/null 2>&1; then
        warn "npm is unavailable after the Node.js phase; continuing without runtime prebuild."
        return
    fi

    local user="${AI_WORKSPACE_RUNTIME_USER:-ubuntu}"
    local home="${AI_WORKSPACE_RUNTIME_HOME:-/home/$user}"
    local console_repo="${XWORKSPACE_CONSOLE_SOURCE_REPO:-$XWORKSPACE_CONSOLE_REPO_URL}"
    local console_ref="${XWORKSPACE_CONSOLE_SOURCE_VERSION:-main}"
    local qmd_repo qmd_ref openclaw_version
    qmd_repo="${QMD_SOURCE_REPO:-$(read_playbook_default roles/vhosts/qmd/defaults/main.yml qmd_source_repo)}"
    qmd_ref="${QMD_VERSION:-$(read_playbook_default roles/vhosts/qmd/defaults/main.yml qmd_version)}"
    openclaw_version="$(read_playbook_default roles/vhosts/gateway_openclaw/defaults/main.yml gateway_openclaw_required_version)"

    if ! ensure_runtime_build_user "$user" "$home"; then
        return
    fi

    info "Starting load-adaptive runtime prebuild (current limit $(dynamic_parallel_job_limit))..."
    reset_bounded_jobs
    run_bounded "build:console" prebuild_console_dashboard \
        "$user" "$home" "$console_repo" "$console_ref" "$home/xworkspace-console" \
        "$AI_WORKSPACE_PREFETCH_DIR/npm-cache/console"
    run_bounded "build:qmd" prebuild_qmd_runtime \
        "$user" "$home" "$qmd_repo" "$qmd_ref" "$home/.local/src/qmd" \
        "$AI_WORKSPACE_PREFETCH_DIR/npm-cache/qmd"
    if [ -n "$openclaw_version" ]; then
        run_bounded "package:openclaw" preinstall_openclaw_runtime \
            "$user" "$home" "$openclaw_version" "$AI_WORKSPACE_PREFETCH_DIR/npm-cache/openclaw"
    fi
    if ! wait_for_bounded_jobs; then
        warn "One or more runtime prebuild jobs failed; the standard Ansible tasks will retry them serially."
        return
    fi
    success "Runtime prebuild completed."
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
    local health_url=${4:-}
    local detail="not detected"
    local state="inactive"
    local http_status=""

    if command -v systemctl >/dev/null 2>&1; then
        local unit
        for unit in $unit_patterns; do
            if systemctl --user is-active --quiet "$unit" 2>/dev/null; then
                state="active"
                detail="systemd-user:$unit"
                break
            fi
            if systemctl is-active --quiet "$unit" 2>/dev/null; then
                state="active"
                detail="systemd:$unit"
                break
            fi
        done
    fi

    if [ "$state" != "active" ] && [ -n "$port" ]; then
        if command -v ss >/dev/null 2>&1 && ss -ltn "( sport = :$port )" 2>/dev/null | grep -q ":$port"; then
            state="active"
            detail="port:$port"
        elif command -v lsof >/dev/null 2>&1 && lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
            state="active"
            detail="port:$port"
        fi
    fi

    if [ -n "$health_url" ] && command -v curl >/dev/null 2>&1; then
        http_status="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 2 --max-time 5 "$health_url" 2>/dev/null || true)"
        case "$http_status" in
            2*|3*|401)
                state="active"
                detail="${detail};http:${http_status}"
                ;;
            '') detail="${detail};http:unreachable" ;;
            *) detail="${detail};http:${http_status}" ;;
        esac
    fi

    printf '  %-28s : %-8s (%s)\n' "$label" "$state" "$detail"
}

cli_status_line() {
    local label=$1
    local command_name=$2
    local version

    if ! command -v "$command_name" >/dev/null 2>&1; then
        printf '  %-28s : unavailable\n' "$label"
        return
    fi

    version="$("$command_name" --version 2>/dev/null | head -n 1 || true)"
    if [ -z "$version" ]; then
        version="unknown"
    fi
    printf '  %-28s : %s\n' "$label" "$version"
}

write_service_status() {
    local output_file=$1
    shift
    service_status_line "$@" > "$output_file"
}

print_parallel_service_statuses() {
    local status_dir
    local labels=(
        "Portal / Console"
        "XWorkMate Bridge"
        "OpenClaw"
        "QMD"
        "Hermes"
        "PostgreSQL"
        "Vault"
        "LiteLLM"
    )
    local units=(
        "xworkspace-console.service xworkspace-api.service"
        "xworkmate-bridge.service xworkspace-bridge.service"
        "xworkspace-openclaw.service openclaw-gateway.service openclaw.service"
        "qmd-mcp.service xworkspace-qmd.service qmd.service qdrant.service"
        "acp-hermes.service xworkspace-hermes.service hermes.service"
        "postgresql.service postgresql@17-main.service postgresql@16-main.service postgresql@15-main.service xworkspace-postgres.service"
        "xworkspace-vault.service vault.service"
        "xworkspace-litellm.service litellm-proxy.service litellm.service"
    )
    local ports=("17000" "8787" "18789" "8181" "3920" "5432" "8200" "${AI_WORKSPACE_LITELLM_PORT}")
    local urls=(
        "http://127.0.0.1:17000/"
        "http://127.0.0.1:8787/"
        "http://127.0.0.1:18789/channels"
        "http://127.0.0.1:8181/"
        "http://127.0.0.1:3920/"
        ""
        "http://127.0.0.1:8200/v1/sys/health"
        "http://127.0.0.1:${AI_WORKSPACE_LITELLM_PORT}/health"
    )

    if command -v systemctl >/dev/null 2>&1; then
        labels+=("Runtime desktop/browser")
        units+=("xworkspace-shell.service display-manager.service gdm.service lightdm.service")
        ports+=("")
        urls+=("")
    fi

    local index

    status_dir="$(mktemp -d)"
    reset_bounded_jobs
    for index in "${!labels[@]}"; do
        run_bounded "status:$index" write_service_status "$status_dir/$index" \
            "${labels[$index]}" "${units[$index]}" "${ports[$index]}" "${urls[$index]}"
    done
    if ! wait_for_bounded_jobs; then
        rm -rf "$status_dir"
        error "Parallel service status collection failed."
    fi
    for index in "${!labels[@]}"; do
        cat "$status_dir/$index"
    done
    rm -rf "$status_dir"
}

print_deployment_summary() {
    local domain=${SERVER_DOMAIN:-${XWORKMATE_BRIDGE_DOMAIN:-${BRIDGE_DOMAIN:-${ACP_BRIDGE_DOMAIN:-xworkmate-bridge.svc.plus}}}}
    local token=$1
    local vault_token="${VAULT_SERVER_ROOT_ACCESS_TOKEN:-$token}"
    local vault_token_display="$vault_token"
    local bridge_url="https://${domain}"
    local portal_url="http://127.0.0.1:17000"
    local is_darwin=false

    if [ "$(detect_os)" = "darwin" ]; then
        is_darwin=true
    fi

    local bridge_label="唯一公开"
    if [ "${XWORKMATE_BRIDGE_PUBLIC_ACCESS:-true}" != "true" ] || [ "$is_darwin" = "true" ]; then
        bridge_url="http://127.0.0.1:8787"
        bridge_label="本地"
    fi
    if [ "$vault_token" = "$token" ]; then
        vault_token_display="same as AI_WORKSPACE_AUTH_TOKEN"
    fi

    local cred_label="[一次性凭据]（仅显示一次）"
    if [ "$is_darwin" = "true" ]; then
        cred_label="[请安全保存到 MacOS KeyStore，可从 ~/.ai_workspace_auth_token 重复查看]"
    fi

    cat <<EOF

================ AI Workspace 部署摘要 ================
[访问入口]
  Workspace Portal (Console) : ${portal_url}      (本地)
  XWorkMate Bridge           : ${bridge_url}   ← ${bridge_label}
  LiteLLM API Endpoint       : http://127.0.0.1:${AI_WORKSPACE_LITELLM_PORT}      (本地)

${cred_label}
  AI_WORKSPACE_AUTH_TOKEN    : ${token}
  Vault root token           : ${vault_token_display}
  LiteLLM API Token          : same as AI_WORKSPACE_AUTH_TOKEN

[服务状态]
EOF
    print_parallel_service_statuses

    cat <<'EOF'

[Agent CLI]
EOF
    cli_status_line "opencode" "opencode"
    cli_status_line "gemini" "gemini"
    cli_status_line "codex" "codex"
    cli_status_line "claude" "claude"
    cat <<'EOF'
===============================================================

Save the one-time credentials above in a private location.
EOF
}

if [ "${AI_WORKSPACE_LIBRARY_MODE:-false}" = "true" ]; then
    if (return 0 2>/dev/null); then
        return 0
    fi
    exit 0
fi

uninstall_ai_workspace() {
    local purge=false
    if [ "${1:-}" = "--purge" ]; then
        purge=true
    fi

    info "Starting AI Workspace uninstallation..."

    if [ "$(detect_os)" = "darwin" ]; then
        info "Stopping and removing macOS launch agents..."
        for svc in api console litellm openclaw vault ttyd bridge qmd hermes; do
            launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/plus.svc.xworkspace.$svc.plist" >/dev/null 2>&1 || true
            rm -f "$HOME/Library/LaunchAgents/plus.svc.xworkspace.$svc.plist"
        done
        stop_managed_pid "$HOME/.local/state/xworkspace/xworkspace-api.pid" >/dev/null 2>&1 || true
        stop_managed_pid "$HOME/.local/state/xworkspace/xworkspace-console.pid" >/dev/null 2>&1 || true

        if [ "$purge" = "true" ]; then
            info "Purging AI Workspace data on macOS..."
            rm -rf "$HOME/.config/xworkspace"
            rm -rf "$HOME/.local/state/xworkspace"
            rm -rf "$HOME/.ai_workspace_auth_token"
            rm -rf "$HOME/.vault_password"
            rm -rf "$HOME/.openclaw"
            rm -rf "/tmp/xworkspace-core-skills"
            rm -rf "/tmp/xworkmate-bridge"
            rm -rf "/tmp/ai-workspace-deploy"
        fi
    else
        info "Stopping and removing Linux systemd services..."
        if command -v systemctl >/dev/null 2>&1; then
            for svc in xworkspace-litellm xworkspace-qmd xworkspace-api xworkspace-console xworkspace-openclaw xworkmate-bridge xworkspace-ttyd vault postgresql xworkspace-hermes; do
                systemctl --user stop "$svc.service" >/dev/null 2>&1 || true
                systemctl --user disable "$svc.service" >/dev/null 2>&1 || true
                rm -f "$HOME/.config/systemd/user/$svc.service"
            done
            systemctl --user daemon-reload >/dev/null 2>&1 || true
            
            # System-wide services
            for svc in xworkspace-litellm xworkspace-qmd xworkspace-api xworkspace-console xworkspace-openclaw xworkmate-bridge xworkspace-ttyd vault postgresql xworkspace-hermes; do
                if systemctl is-active --quiet "$svc.service" 2>/dev/null; then
                    run_as_root systemctl stop "$svc.service" >/dev/null 2>&1 || true
                    run_as_root systemctl disable "$svc.service" >/dev/null 2>&1 || true
                    run_as_root rm -f "/etc/systemd/system/$svc.service"
                fi
            done
            run_as_root systemctl daemon-reload >/dev/null 2>&1 || true
        fi
        
        if command -v docker >/dev/null 2>&1; then
            info "Removing docker containers..."
            for container in vault litellm db ai-workspace-console xworkmate-bridge qmd openclaw hermes xworkspace-ttyd; do
                docker stop "$container" >/dev/null 2>&1 || true
                docker rm -f "$container" >/dev/null 2>&1 || true
            done
        fi

        if [ "$purge" = "true" ]; then
            info "Purging AI Workspace data on Linux..."
            rm -rf "$HOME/.config/xworkspace"
            rm -rf "$HOME/.local/state/xworkspace"
            rm -rf "$HOME/.ai_workspace_auth_token"
            rm -rf "$HOME/.vault_password"
            rm -rf "$HOME/.openclaw"
            rm -rf "/tmp/xworkspace-core-skills"
            rm -rf "/tmp/xworkmate-bridge"
            rm -rf "/tmp/ai-workspace-deploy"
            rm -rf "$HOME/.config/systemd/user/plus.svc.xworkspace."*
            if [ "$(id -u)" = "0" ] || sudo -n true 2>/dev/null; then
                run_as_root rm -rf "/opt/ai-workspace" >/dev/null 2>&1 || true
                run_as_root rm -rf "/etc/ai-workspace" >/dev/null 2>&1 || true
            fi
        fi
    fi

    success "AI Workspace uninstallation complete."
    exit 0
}

if [ "${AI_WORKSPACE_BOOTSTRAP_LIB_ONLY:-false}" = "true" ]; then
    if [ "${BASH_SOURCE[0]}" != "$0" ]; then
        return 0
    fi
    exit 0
fi

info "Starting AI Workspace All-in-One Bootstrap..."

# 1. Install prerequisites (git, curl, ansible) if missing
OS_NAME="$(detect_os)"

if [ "$OS_NAME" = "darwin" ]; then
    require_or_install_macos_cmds
fi

if [ "$OS_NAME" = "linux" ] || [ "$OS_NAME" = "darwin" ]; then
    if [ "$OS_NAME" = "linux" ]; then
        acquire_deployment_lock
        wait_for_apt_locks
        ensure_public_edge_firewall_ports
    fi
    # Skip offline bootstrap when running a subcommand that handles its own flow
    case "${1:-}" in
        sync|uninstall|backup|restore|migrate) ;;
        *)
            if try_bootstrap_from_offline_package; then
                exit 0
            fi
            ;;
    esac
fi

if ! command -v ansible-playbook >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
    install_prerequisites "$OS_NAME"
fi

# Git may have been installed after the early best-effort configuration above.
git config --global --add safe.directory '*' || true

export XWORKSPACE_CONSOLE_PUBLIC_ACCESS="${XWORKSPACE_CONSOLE_PUBLIC_ACCESS:-false}"
export XWORKMATE_BRIDGE_PUBLIC_ACCESS="${XWORKMATE_BRIDGE_PUBLIC_ACCESS:-true}"
export GATEWAY_OPENCLAW_PUBLIC_ACCESS="${GATEWAY_OPENCLAW_PUBLIC_ACCESS:-false}"
export VAULT_PUBLIC_ACCESS="${VAULT_PUBLIC_ACCESS:-false}"
export LITELLM_CADDY_CONFIG_ENABLED="${LITELLM_CADDY_CONFIG_ENABLED:-false}"
export VAULT_DEPLOY_MODE="${VAULT_DEPLOY_MODE:-standalone}"
export XWORKMATE_BRIDGE_VALIDATION_BASE_URL="${XWORKMATE_BRIDGE_VALIDATION_BASE_URL:-http://127.0.0.1:8787}"

# Check for commands
if [ "${1:-}" = "sync" ]; then
    info "Starting AI Workspace offline package synchronization..."
    if [ "${AI_WORKSPACE_OFFLINE_ACTIVE:-false}" = "true" ]; then
        error "Already running from offline package. Sync is not required."
    fi
    if offline_mode_is_off; then
        error "Offline package sync disabled by AI_WORKSPACE_OFFLINE_MODE=$AI_WORKSPACE_OFFLINE_MODE"
    fi
    if [ "$(detect_os)" != "linux" ]; then
        error "Offline package synchronization is only supported on Linux."
    fi

    target="$(detect_offline_target)" || error "No supported offline package target detected for this host."
    filename="$(offline_package_filename "$target")"
    source="$(offline_package_source "$filename")"
    if [ -z "$source" ]; then
        error "No offline package source is configured."
    fi

    root="$(prepare_offline_package_root "$source" "$filename")" || error "Unable to prepare offline package from $source."
    success "Offline base package successfully synchronized and extracted to: $root"

    success "Phase 1 complete. You can now run the script again without arguments to begin Phase 2 (deployment)."
    exit 0
elif [ "${1:-}" = "uninstall" ]; then
    uninstall_ai_workspace "${2:-}"
elif [ "${1:-}" = "backup" ]; then
    backup_file="ai-workspace-backup.tar.gz.enc"
    while [[ $# -gt 0 ]]; do
        case $1 in
            --output)
                backup_file="$2"
                shift 2
                ;;
            backup)
                shift
                ;;
            *)
                error "Unknown argument: $1"
                ;;
        esac
    done

    # resolve absolute path for backup_file
    case "$backup_file" in
        /*) ;;
        *) backup_file="$PWD/$backup_file" ;;
    esac

    info "Starting AI Workspace backup to $backup_file..."
    wait_for_apt_locks
    
    ansible-playbook -i '127.0.0.1,' -c local setup-ai-workspace-backup.yml \
        --vault-password-file "$VAULT_FILE" \
        -e "backup_output_file=$backup_file" \
        "${ANSIBLE_EXTRA_VARS[@]}" || error "Backup failed."
    
    success "Backup complete: $backup_file"
    exit 0
elif [ "${1:-}" = "restore" ]; then
    restore_file=""
    while [[ $# -gt 0 ]]; do
        case $1 in
            --input)
                restore_file="$2"
                shift 2
                ;;
            restore)
                shift
                ;;
            *)
                error "Unknown argument: $1"
                ;;
        esac
    done

    if [ -z "$restore_file" ]; then
        error "Restore requires --input <file>"
    fi
    if [ ! -f "$restore_file" ]; then
        error "Backup file not found: $restore_file"
    fi

    # resolve absolute path for restore_file
    case "$restore_file" in
        /*) ;;
        *) restore_file="$PWD/$restore_file" ;;
    esac

    info "Starting AI Workspace restore from $restore_file..."
    wait_for_apt_locks
    
    ansible-playbook -i '127.0.0.1,' -c local setup-ai-workspace-restore.yml \
        --vault-password-file "$VAULT_FILE" \
        -e "backup_input_file=$restore_file" \
        "${ANSIBLE_EXTRA_VARS[@]}" || error "Restore failed."
    
    success "Restore complete."
    exit 0
elif [ "${1:-}" = "migrate" ]; then
    source_host=""
    while [[ $# -gt 0 ]]; do
        case $1 in
            --source)
                source_host="$2"
                shift 2
                ;;
            migrate)
                shift
                ;;
            *)
                error "Unknown argument: $1"
                ;;
        esac
    done

    if [ -z "$source_host" ]; then
        error "Migration requires --source <user@host>"
    fi
    
    # Parse user and host
    migrate_user="${source_host%%@*}"
    migrate_host="${source_host#*@}"
    if [ "$migrate_user" = "$migrate_host" ]; then
        migrate_user="ubuntu" # default user if not specified
    fi

    info "Starting AI Workspace migration from $source_host..."
    wait_for_apt_locks
    
    # Run the migration playbook
    ansible-playbook -i '127.0.0.1,' -c local setup-ai-workspace-migration.yml \
        --vault-password-file "$VAULT_FILE" \
        -e "migrate_source_host=$migrate_host" \
        -e "migrate_source_user=$migrate_user" \
        "${ANSIBLE_EXTRA_VARS[@]}" || error "Migration failed."
    
    success "AI Workspace migration complete."
    exit 0
fi
# 2. Clone Repository
if [ -n "$PLAYBOOK_DIR" ]; then
    [ -d "$PLAYBOOK_DIR" ] || error "PLAYBOOK_DIR does not exist: $PLAYBOOK_DIR"
    info "Using local playbooks repository at $PLAYBOOK_DIR"
    cd "$PLAYBOOK_DIR"
    if [ "${AI_WORKSPACE_OFFLINE_ACTIVE:-false}" = "true" ]; then
        info "Checking for latest playbook updates from GitHub..."
        if curl -m 3 -sI https://github.com >/dev/null 2>&1; then
            info "Network is reachable. Updating local offline playbooks repository..."
            git fetch origin >/dev/null 2>&1 && git reset --hard origin/"$BRANCH" >/dev/null 2>&1 || true
        else
            info "Network is unreachable. Using cached offline playbooks."
        fi
    fi
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
if [ "$(detect_os)" = "darwin" ]; then
    patch_playbook_vault_macos
    patch_playbook_common_macos
    patch_playbook_postgres_macos
    patch_playbook_litellm_macos
    patch_playbook_console_macos
    patch_playbook_openclaw_macos
fi
prefetch_independent_sources
ensure_core_skills_source
ensure_xworkmate_bridge_source

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
append_var "LITELLM_CADDY_CONFIG_ENABLED"       "litellm_caddy_config_enabled"
append_var "XWORKSPACE_CONSOLE_PUBLIC_ACCESS"   "xworkspace_console_public_access"
append_var "XWORKMATE_BRIDGE_PUBLIC_ACCESS"     "xworkmate_bridge_public_access"
append_var "XWORKMATE_BRIDGE_DOMAIN"            "xworkmate_bridge_domain"
append_var "XWORKMATE_BRIDGE_VALIDATION_BASE_URL" "xworkmate_bridge_validation_base_url"
append_var "GATEWAY_OPENCLAW_PUBLIC_ACCESS"     "gateway_openclaw_public_access"
append_var "VAULT_PUBLIC_ACCESS"                "vault_public_access"
append_var "VAULT_DEPLOY_MODE"                  "vault_deploy_mode"
append_var "XWORKSPACE_CONSOLE_ENABLE_XRDP"     "xworkspace_console_enable_xrdp"
append_var "AI_WORKSPACE_RUNTIME_MODES"         "ai_workspace_runtime_modes"
append_var "POSTGRESQL_DEPLOY_MODE"             "postgresql_deploy_mode"
append_var "AI_WORKSPACE_APT_LOCK_TIMEOUT"      "ai_workspace_apt_lock_timeout"
append_var "XWORKSPACE_CONSOLE_SOURCE_REPO"     "xworkspace_console_source_repo"
append_var "XWORKSPACE_CONSOLE_SOURCE_VERSION"  "xworkspace_console_source_version"
append_var "XWORKSPACE_CONSOLE_RUNTIME_ARCHIVE" "xworkspace_console_runtime_archive"
append_var "QMD_SOURCE_REPO"                    "qmd_source_repo"
append_var "QMD_VERSION"                        "qmd_version"
append_var "QMD_RUNTIME_ARCHIVE"                 "qmd_runtime_archive"
append_var "LITELLM_SOURCE_REPO"                "litellm_source_repo"
append_var "LITELLM_VERSION"                    "litellm_version"
append_var "OPENCLAW_MULTI_SESSION_PLUGIN_PACKAGE_SPEC" "gateway_openclaw_multi_session_plugin_package_spec"

append_var "DEEPSEEK_API_KEY"                   "litellm_deepseek_api_key"
append_var "NVIDIA_API_KEY"                     "litellm_nvidia_api_key"
append_var "OLLAMA_API_KEY"                     "litellm_ollama_api_key"
append_var "GEMINI_API_KEY"                     "litellm_gemini_api_key"
append_var "OPENAI_API_KEY"                     "litellm_openai_api_key"
append_var "ANTHROPIC_API_KEY"                  "litellm_anthropic_api_key"

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
ANSIBLE_EXTRA_VARS+=("-e" "agent_skills_quality_gate_fail_on_error=false")

if [ "$(detect_os)" = "darwin" ]; then
    info "Disabling global privilege escalation for macOS..."
    DARWIN_SERVICE_PATH="$HOME/.nix-profile/bin:$HOME/.local/bin:$HOME/.npm-global/bin:$HOME/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin"
    ANSIBLE_EXTRA_VARS+=("-e" "ansible_become=false")
    ANSIBLE_EXTRA_VARS+=("-e" "xworkspace_console_user=$(id -un)")
    ANSIBLE_EXTRA_VARS+=("-e" "xworkspace_console_home=$HOME")
    ANSIBLE_EXTRA_VARS+=("-e" "xworkspace_console_root=$HOME/.local/state/ai-workspace")
    ANSIBLE_EXTRA_VARS+=("-e" "xworkspace_console_config_dir=$HOME/.config/ai-workspace")
    ANSIBLE_EXTRA_VARS+=("-e" "xworkspace_console_scripts_dir=$HOME/xworkspace/scripts")
    ANSIBLE_EXTRA_VARS+=("-e" "xworkspace_console_repo_dir=$XWORKSPACE_CONSOLE_DIR")
    ANSIBLE_EXTRA_VARS+=("-e" "xworkspace_console_source_repo=https://github.com/ai-workspace-lab/xworkspace-console.git")
    ANSIBLE_EXTRA_VARS+=("-e" "xworkspace_console_source_version=main")
    ANSIBLE_EXTRA_VARS+=("-e" "xworkspace_console_api_working_dir=$XWORKSPACE_CONSOLE_DIR/api")
    ANSIBLE_EXTRA_VARS+=("-e" "xworkspace_console_api_exec=/usr/bin/env go run .")
    ANSIBLE_EXTRA_VARS+=("-e" "xworkspace_console_group=staff")
    ANSIBLE_EXTRA_VARS+=("-e" "xworkspace_console_ttyd_binary_path=$(command -v ttyd)")
    ANSIBLE_EXTRA_VARS+=("-e" "agent_skills_user=$(id -un)")
    ANSIBLE_EXTRA_VARS+=("-e" "agent_skills_group=staff")
    ANSIBLE_EXTRA_VARS+=("-e" "agent_skills_home=$HOME")
    ANSIBLE_EXTRA_VARS+=("-e" "gateway_openclaw_service_user=$(id -un)")
    ANSIBLE_EXTRA_VARS+=("-e" "gateway_openclaw_service_group=staff")
    ANSIBLE_EXTRA_VARS+=("-e" "gateway_openclaw_home=$HOME")
    ANSIBLE_EXTRA_VARS+=("-e" "gateway_openclaw_compile_cache_dir=$HOME/.cache/openclaw-compile-cache")
    ANSIBLE_EXTRA_VARS+=("-e" "gateway_openclaw_service_path=$DARWIN_SERVICE_PATH")
    ANSIBLE_EXTRA_VARS+=("-e" "gateway_openclaw_multi_session_plugin_dir=$OPENCLAW_MULTI_SESSION_PLUGIN_DIR")
    # XWorkMate Bridge writes its runtime data under a base dir that defaults to
    # /opt/cloud-neutral on Linux. That path is fine on Linux, but on macOS it
    # is both non-writable under become=false and non-standard for the platform.
    # Relocate it to the Apple-standard per-user app data location instead.
    ANSIBLE_EXTRA_VARS+=("-e" "xworkmate_bridge_base_dir=$HOME/Library/Application Support/cloud-neutral/xworkmate-bridge")
    # PostgreSQL defaults to compose (Docker) mode, which is inappropriate on a
    # native macOS deploy: it pulls in the apt-based docker role and stores the
    # admin password under /root. Use native mode (Homebrew postgresql@16 via the
    # role's macos.yml) and pass the admin password directly so the default
    # /root/.ai_workspace_postgres_password lookup is never attempted.
    ANSIBLE_EXTRA_VARS+=("-e" "postgresql_deploy_mode=native")
    append_secret_var "postgresql_admin_password" "$UNIFIED_AUTH_TOKEN"
    # LiteLLM persists its salt key and DB password under /root by default, which
    # is unreadable/unwritable on macOS, so the "Materialize persisted LiteLLM
    # secrets" assert sees empty values. Source them from the shared token, like
    # the other services on macOS.
    append_secret_var "litellm_salt_key" "$UNIFIED_AUTH_TOKEN"
    append_secret_var "litellm_database_password" "$UNIFIED_AUTH_TOKEN"
    # litellm_config_dir defaults to /etc/litellm (root-owned). Relocate to a
    # user-writable path on macOS; config.yaml/litellm.env derive from it.
    ANSIBLE_EXTRA_VARS+=("-e" "litellm_config_dir=$HOME/.config/litellm")
else
    LINUX_CONSOLE_USER="$(linux_default_console_user)"
    LINUX_CONSOLE_HOME="$(linux_default_console_home "$LINUX_CONSOLE_USER")"
    info "Deploying AI Workspace runtime as $LINUX_CONSOLE_USER under $LINUX_CONSOLE_HOME..."
    append_linux_console_identity_vars "$LINUX_CONSOLE_USER" "$LINUX_CONSOLE_HOME"
fi

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
wait_for_apt_locks
RET=0
if [ "$AI_WORKSPACE_SPLIT_PHASES" = "true" ]; then
    info "Running AI Workspace preflight..."
    ansible-playbook -i '127.0.0.1,' -c local setup-ai-workspace-preflight.yml \
        --vault-password-file "$VAULT_FILE" \
        "${ANSIBLE_EXTRA_VARS[@]}" || RET=$?
    if [ "$RET" -eq 0 ]; then
        info "Running serialized Node.js foundation phase..."
        ansible-playbook -i '127.0.0.1,' -c local setup-nodejs.yml \
            --vault-password-file "$VAULT_FILE" \
            "${ANSIBLE_EXTRA_VARS[@]}" || RET=$?
    fi
    if [ "$RET" -eq 0 ]; then
        info "Running remaining AI Workspace runtime phases..."
        ansible-playbook -i '127.0.0.1,' -c local setup-ai-workspace-runtime.yml \
            --vault-password-file "$VAULT_FILE" \
            "${ANSIBLE_EXTRA_VARS[@]}" || RET=$?
    fi
else
    info "Running monolithic AI Workspace Playbook..."
    ansible-playbook -i '127.0.0.1,' -c local setup-ai-workspace-all-in-one.yml \
        --vault-password-file "$VAULT_FILE" \
        "${ANSIBLE_EXTRA_VARS[@]}" || RET=$?
fi

if [ $RET -eq 0 ]; then
    success "AI Workspace deployed successfully!"
    print_deployment_summary "$UNIFIED_AUTH_TOKEN"
else
    error "Deployment failed with exit code $RET."
fi
