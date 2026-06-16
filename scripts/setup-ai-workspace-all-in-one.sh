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
XWORKSPACE_CORE_SKILLS_REPO_URL=${XWORKSPACE_CORE_SKILLS_REPO_URL:-"https://github.com/ai-workspace-lab/xworkspace-core-skills.git"}
XWORKSPACE_CORE_SKILLS_DIR=${XWORKSPACE_CORE_SKILLS_DIR:-"/tmp/xworkspace-core-skills"}
XWORKMATE_BRIDGE_REPO_URL=${XWORKMATE_BRIDGE_REPO_URL:-"https://github.com/ai-workspace-lab/xworkmate-bridge.git"}
XWORKMATE_BRIDGE_BRANCH=${XWORKMATE_BRIDGE_BRANCH:-"release/v1.1.4"}
XWORKMATE_BRIDGE_SOURCE_DIR=${XWORKMATE_BRIDGE_SOURCE_DIR:-"/tmp/xworkmate-bridge"}
AUTH_TOKEN_FILE=${AI_WORKSPACE_AUTH_TOKEN_FILE:-"$HOME/.ai_workspace_auth_token"}
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
    load_ceiling="$(awk -v load="$load_average" 'BEGIN { value=int(load); if (load > value) value++; print value }')"
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
                if ! curl -fL --retry 3 --retry-delay 5 --continue-at - -o "$partial" "$resolved_source"; then
                    rm -f "$partial"
                    curl -fL --retry 3 --retry-delay 5 -o "$partial" "$resolved_source" || return 1
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

run_offline_installer() {
    local root=$1
    local target=$2
    local installer="$root/scripts/ai-workspace-offline-install.sh"
    local env_args=(
        "AI_WORKSPACE_OFFLINE_ACTIVE=true"
        "AI_WORKSPACE_DEPLOYMENT_LOCK_HELD=true"
    )
    local env_name

    [ -f "$installer" ] || return 1
    validate_offline_package_target "$root" "$target"
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
    if run_offline_installer "$root" "$target"; then
        return 0
    fi

    error "Offline package installer failed after making deployment changes; online fallback was not started."
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

macos_xworkmate_bridge_bin() {
    local bridge_dir="$HOME/.local/src/xworkmate-bridge"
    info "Building XWorkmate Bridge locally under $bridge_dir..."
    mkdir -p "$HOME/.local/src"
    if [ ! -d "$bridge_dir/.git" ]; then
        git clone "${XWORKMATE_BRIDGE_REPO_URL:-https://github.com/ai-workspace-lab/xworkmate-bridge.git}" "$bridge_dir" >&2
    fi
    (cd "$bridge_dir" && git fetch origin >&2 && git reset --quiet --hard "origin/${XWORKMATE_BRIDGE_BRANCH:-main}" >&2 && go build -o xworkmate-go-core)
    echo "$bridge_dir/xworkmate-go-core"
}

macos_qmd_bin() {
    local qmd_dir="$HOME/.local/src/qmd"
    local qmd_bin="$qmd_dir/bin/qmd"
    info "Building QMD locally under $qmd_dir..."
    mkdir -p "$HOME/.local/src"
    if [ ! -d "$qmd_dir/.git" ]; then
        local qmd_repo_url="${QMD_SOURCE_REPO:-https://github.com/ai-workspace-lab/qmd.git}"
        qmd_repo_url="${qmd_repo_url#file://}"
        git clone "$qmd_repo_url" "$qmd_dir" >&2
    fi
    (cd "$qmd_dir" && npm install >&2 && npm run build >&2)
    printf '%s\n' "$qmd_bin"
}

macos_hermes_bin() {
    local hermes_dir="$HOME/.local/share/xworkspace/bin"
    local hermes_bin="$hermes_dir/hermes"
    if [ -x "$hermes_bin" ]; then
        printf '%s\n' "$hermes_bin"
        return
    fi
    info "Creating Hermes Python shim at $hermes_bin..."
    mkdir -p "$hermes_dir"
    cat << 'EOF' > "$hermes_bin"
#!/usr/bin/env python3
import json
import sys
import uuid

def respond(request, result=None, error=None):
    payload = {"jsonrpc": "2.0", "id": request.get("id")}
    if error is not None:
        payload["error"] = {"code": -32000, "message": str(error)}
    else:
        payload["result"] = result if result is not None else {}
    print(json.dumps(payload, separators=(",", ":")), flush=True)

for line in sys.stdin:
    try:
        request = json.loads(line)
    except Exception:
        continue
    method = request.get("method")
    if method == "initialize":
        respond(request, {
            "protocolVersion": 1,
            "authMethods": [],
            "agentCapabilities": {
                "loadSession": True,
                "promptCapabilities": {"embeddedContext": True, "image": False},
                "sessionCapabilities": {"resume": {}, "fork": {}, "list": {}},
            },
        })
    elif method == "session/new":
        respond(request, {"sessionId": "hermes-shim-" + uuid.uuid4().hex})
    elif method in ("session/prompt", "session/start", "session/message"):
        params = request.get("params") or {}
        prompt = params.get("prompt") or params.get("taskPrompt") or ""
        text = "pong" if "pong" in str(prompt).lower() else "Hermes ACP shim is online."
        respond(request, {"output": text, "text": text})
    else:
        respond(request, {"ok": True})
EOF
    chmod +x "$hermes_bin"
    printf '%s\n' "$hermes_bin"
}

install_macos_agent_clis() {
    local prefix="$HOME/.local/share/xworkspace/node"
    info "Installing local Agent CLIs (opencode-ai, gemini-cli, codex, claude) to $prefix..."
    mkdir -p "$prefix"
    npm install --prefix "$prefix" opencode-ai @google/gemini-cli @openai/codex @anthropic-ai/claude-code >/dev/null 2>&1 || {
        warn "Failed to install NPM CLI tools. You may need to install them manually."
    }
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
    git -C "$dest" checkout --force --detach FETCH_HEAD
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
            2*|3*|401|400) return 0 ;;
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
    local ports=("17000" "8787" "18789" "8181" "3920" "5432" "8200" "4000")
    local urls=(
        "http://127.0.0.1:17000/"
        "http://127.0.0.1:8787/"
        "http://127.0.0.1:18789/channels"
        "http://127.0.0.1:8181/"
        "http://127.0.0.1:3920/"
        ""
        "http://127.0.0.1:8200/v1/sys/health"
        "http://127.0.0.1:4000/health"
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

cli_status_line() {
    local label=$1
    local bin=$2
    local state="missing"
    local detail="not in PATH"

    if command -v "$bin" >/dev/null 2>&1; then
        state="available"
        detail="$("$bin" --version 2>/dev/null | head -n 1 || command -v "$bin")"
    elif [ -x "$HOME/.local/share/xworkspace/node/bin/$bin" ]; then
        state="available"
        detail="$HOME/.local/share/xworkspace/node/bin/$bin"
    fi

    printf '  %-28s : %-9s (%s)\n' "$label" "$state" "$detail"
}

print_deployment_summary() {
    local domain=${SERVER_DOMAIN:-${XWORKMATE_BRIDGE_DOMAIN:-${BRIDGE_DOMAIN:-${ACP_BRIDGE_DOMAIN:-acp-bridge.onwalk.net}}}}
    local token=$1
    local vault_token="${VAULT_SERVER_ROOT_ACCESS_TOKEN:-$token}"
    local vault_token_display="$vault_token"
    local bridge_url="https://${domain}"
    local portal_url="http://127.0.0.1:17000"

    if [ "${XWORKMATE_BRIDGE_PUBLIC_ACCESS:-true}" != "true" ]; then
        bridge_url="http://127.0.0.1:8787"
    fi
    if [ "$vault_token" = "$token" ]; then
        vault_token_display="same as AI_WORKSPACE_AUTH_TOKEN"
    fi

    cat <<EOF

================ AI Workspace 部署摘要 ================
[访问入口]
  Workspace Portal (Console) : ${portal_url}      (本地)
  XWorkMate Bridge           : ${bridge_url}   ← 唯一公开

[一次性凭据]（仅显示一次）
  AI_WORKSPACE_AUTH_TOKEN    : ${token}
  Vault root token           : ${vault_token_display}

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

deploy_launch_agent() {
    local label=$1
    local workdir=$2
    local command=$3
    local stdout_log=$4
    local stderr_log=$5
    local plist_dir="$HOME/Library/LaunchAgents"
    local plist="$plist_dir/$label.plist"
    local domain
    domain="gui/$(id -u)"

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
    bridge_bin="$(macos_xworkmate_bridge_bin)"
    qmd_bin="$(macos_qmd_bin)"
    hermes_bin="$(macos_hermes_bin)"

    launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/plus.svc.xworkspace.litellm.plist" >/dev/null 2>&1 || true
    launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/plus.svc.xworkspace.openclaw.plist" >/dev/null 2>&1 || true
    launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/plus.svc.xworkspace.vault.plist" >/dev/null 2>&1 || true
    launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/plus.svc.xworkspace.ttyd.plist" >/dev/null 2>&1 || true
    launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/plus.svc.xworkspace.bridge.plist" >/dev/null 2>&1 || true
    launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/plus.svc.xworkspace.qmd.plist" >/dev/null 2>&1 || true
    launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/plus.svc.xworkspace.hermes.plist" >/dev/null 2>&1 || true

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

    info "Starting XWorkMate Bridge on http://127.0.0.1:8787/ ..."
    deploy_launch_agent \
        "plus.svc.xworkspace.bridge" \
        "$HOME" \
        "exec /usr/bin/env PATH='$tool_path' INTERNAL_SERVICE_TOKEN=\"\$(cat '$config_dir/auth-token')\" '$bridge_bin' serve --listen 127.0.0.1:8787" \
        "$state_dir/bridge.log" \
        "$state_dir/bridge.err.log"
    wait_for_url "http://127.0.0.1:8787/"

    info "Starting QMD MCP on http://127.0.0.1:8181/mcp ..."
    deploy_launch_agent \
        "plus.svc.xworkspace.qmd" \
        "$HOME" \
        "exec /usr/bin/env PATH='$tool_path' QMD_EMBED_API_BASE_URL=https://integrate.api.nvidia.com/v1 QMD_EMBED_MODEL=nvidia/llama-nemotron-embed-1b-v2 '$qmd_bin' mcp --http --port 8181" \
        "$state_dir/qmd.log" \
        "$state_dir/qmd.err.log"
    wait_for_url "http://127.0.0.1:8181/mcp"

    info "Starting Hermes ACP Adapter on http://127.0.0.1:3920/acp ..."
    deploy_launch_agent \
        "plus.svc.xworkspace.hermes" \
        "$HOME" \
        "exec /usr/bin/env PATH='$tool_path' HERMES_ADAPTER_AUTH_TOKEN=\"\$(cat '$config_dir/auth-token')\" '$bridge_bin' adapter hermes --listen 127.0.0.1:3920 --hermes-bin '$hermes_bin'" \
        "$state_dir/hermes.log" \
        "$state_dir/hermes.err.log"
    wait_for_url "http://127.0.0.1:3920/acp"
}

deploy_macos_local() {
    require_or_install_macos_cmds
    install_macos_agent_clis

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
    launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/plus.svc.xworkspace.bridge.plist" >/dev/null 2>&1 || true
    launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/plus.svc.xworkspace.qmd.plist" >/dev/null 2>&1 || true
    launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/plus.svc.xworkspace.hermes.plist" >/dev/null 2>&1 || true
    ensure_port_available_for_repo 8788 "$console_dir"
    ensure_port_available 8787
    ensure_port_available_for_repo 17000 "$console_dir"
    ensure_port_available 4000
    ensure_port_available 18789
    ensure_port_available 8200
    ensure_port_available 7681
    ensure_port_available 8181
    ensure_port_available 3920

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

if [ "${AI_WORKSPACE_LIBRARY_MODE:-false}" = "true" ]; then
    if (return 0 2>/dev/null); then
        return 0
    fi
    exit 0
fi

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
    print_deployment_summary "$UNIFIED_AUTH_TOKEN"
    exit 0
fi

if [ "$OS_NAME" = "linux" ]; then
    acquire_deployment_lock
    wait_for_apt_locks
    if try_bootstrap_from_offline_package; then
        exit 0
    fi
fi

if ! command -v ansible-playbook >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
    install_prerequisites "$OS_NAME"
fi

export XWORKSPACE_CONSOLE_PUBLIC_ACCESS="${XWORKSPACE_CONSOLE_PUBLIC_ACCESS:-false}"
export XWORKMATE_BRIDGE_PUBLIC_ACCESS="${XWORKMATE_BRIDGE_PUBLIC_ACCESS:-true}"
export GATEWAY_OPENCLAW_PUBLIC_ACCESS="${GATEWAY_OPENCLAW_PUBLIC_ACCESS:-false}"
export VAULT_PUBLIC_ACCESS="${VAULT_PUBLIC_ACCESS:-false}"
export LITELLM_CADDY_CONFIG_ENABLED="${LITELLM_CADDY_CONFIG_ENABLED:-false}"
export VAULT_DEPLOY_MODE="${VAULT_DEPLOY_MODE:-standalone}"
export XWORKMATE_BRIDGE_VALIDATION_BASE_URL="${XWORKMATE_BRIDGE_VALIDATION_BASE_URL:-http://127.0.0.1:8787}"

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
