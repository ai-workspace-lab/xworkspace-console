#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APT_DIR="${ROOT}/packages/apt"
BIN_DIR="${ROOT}/packages/bin"
IMAGE_DIR="${ROOT}/packages/images"
NPM_CACHE_DIR="${ROOT}/packages/npm-cache"
PIP_WHEEL_DIR="${ROOT}/packages/pip"
STATE_DIR="${AI_WORKSPACE_OFFLINE_STATE_DIR:-/var/lib/ai-workspace/offline}"
AI_WORKSPACE_DEPLOYMENT_LOCK_TIMEOUT="${AI_WORKSPACE_DEPLOYMENT_LOCK_TIMEOUT:-1800}"
AI_WORKSPACE_APT_LOCK_TIMEOUT="${AI_WORKSPACE_APT_LOCK_TIMEOUT:-900}"
APT_SOURCE_FILE="/etc/apt/sources.list.d/ai-workspace-offline.list"
APT_LOCAL_OPTIONS=(
  -o "Dir::Etc::sourcelist=sources.list.d/ai-workspace-offline.list"
  -o "Dir::Etc::sourceparts=-"
  -o "APT::Get::List-Cleanup=0"
)

info() {
  printf '\033[1;34m[INFO]\033[0m %s\n' "$*" >&2
}

warn() {
  printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Run this installer as root or with sudo." >&2
    exit 1
  fi
}

acquire_deployment_lock() {
  if [ "${AI_WORKSPACE_DEPLOYMENT_LOCK_HELD:-false}" = "true" ]; then
    return
  fi
  command -v flock >/dev/null 2>&1 || {
    warn "flock is unavailable; continuing without the deployment serialization lock."
    return
  }

  local lock_file="${AI_WORKSPACE_DEPLOYMENT_LOCK_FILE:-/var/lock/ai-workspace-all-in-one.lock}"
  mkdir -p "$(dirname "${lock_file}")"
  exec 9>"${lock_file}"
  info "Waiting for the AI Workspace deployment lock: ${lock_file}"
  flock -w "${AI_WORKSPACE_DEPLOYMENT_LOCK_TIMEOUT}" 9 || {
    echo "Timed out waiting for another AI Workspace deployment to finish." >&2
    exit 1
  }
  export AI_WORKSPACE_DEPLOYMENT_LOCK_HELD=true
}

wait_for_apt_locks() {
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
      if [ "${busy}" = "false" ] &&
         command -v fuser >/dev/null 2>&1 &&
         [ -e "${lock}" ] &&
         fuser "${lock}" >/dev/null 2>&1; then
        busy=true
      fi
      if [ "${busy}" = "false" ] &&
         command -v lslocks >/dev/null 2>&1 &&
         lslocks -rn -o PATH 2>/dev/null | grep -Fxq "${lock}"; then
        busy=true
      fi
    done

    if [ "${busy}" = "false" ]; then
      return
    fi
    if [ "${waited}" -ge "${AI_WORKSPACE_APT_LOCK_TIMEOUT}" ]; then
      echo "Timed out after ${AI_WORKSPACE_APT_LOCK_TIMEOUT}s waiting for APT/dpkg locks." >&2
      exit 1
    fi
    if [ $((waited % 30)) -eq 0 ]; then
      info "Another package manager is active; waiting for APT/dpkg locks (${waited}s/${AI_WORKSPACE_APT_LOCK_TIMEOUT}s)..."
    fi
    sleep 5
    waited=$((waited + 5))
  done
}

configure_local_apt_repo() {
  if [ ! -d "${APT_DIR}" ] || ! compgen -G "${APT_DIR}/*.deb" >/dev/null; then
    warn "No offline .deb cache found at ${APT_DIR}; skipping local APT repo setup."
    return
  fi

  info "Configuring local APT repository from ${APT_DIR}"
  cat > "${APT_SOURCE_FILE}" <<EOF
deb [trusted=yes] file:${APT_DIR} ./
EOF
  trap 'rm -f "${APT_SOURCE_FILE}"' EXIT
  apt-get "${APT_LOCAL_OPTIONS[@]}" update
}

append_available_package() {
  local -n package_list=$1
  local package=$2
  if apt-cache "${APT_LOCAL_OPTIONS[@]}" show "${package}" >/dev/null 2>&1; then
    package_list+=("${package}")
  fi
}

install_offline_prerequisites() {
  local packages=(git curl ansible ca-certificates unzip)

  if ! command -v docker >/dev/null 2>&1; then
    if apt-cache "${APT_LOCAL_OPTIONS[@]}" show docker-ce >/dev/null 2>&1; then
      packages+=(docker-ce docker-ce-cli containerd.io)
      append_available_package packages docker-buildx-plugin
      append_available_package packages docker-compose-plugin
    elif apt-cache "${APT_LOCAL_OPTIONS[@]}" show docker.io >/dev/null 2>&1; then
      packages+=(docker.io)
      append_available_package packages docker-compose-plugin
    fi
  fi

  wait_for_apt_locks
  info "Installing bootstrap prerequisites from the bundled APT repository"
  DEBIAN_FRONTEND=noninteractive apt-get "${APT_LOCAL_OPTIONS[@]}" install \
    -y --no-install-recommends "${packages[@]}"
}

install_bundled_binaries() {
  if compgen -G "${BIN_DIR}/vault_*_linux_*.zip" >/dev/null; then
    info "Installing bundled Vault binary"
    tmp="$(mktemp -d)"
    unzip -o "${BIN_DIR}"/vault_*_linux_*.zip -d "${tmp}"
    install -m 0755 "${tmp}/vault" /usr/local/bin/vault
    rm -rf "${tmp}"
  fi

  case "$(uname -m)" in
    x86_64|amd64) ttyd_arch=x86_64 ;;
    aarch64|arm64) ttyd_arch=aarch64 ;;
    *) ttyd_arch="" ;;
  esac
  if [ -n "${ttyd_arch}" ] && [ -f "${BIN_DIR}/ttyd.${ttyd_arch}" ]; then
    info "Installing bundled ttyd binary"
    install -m 0755 "${BIN_DIR}/ttyd.${ttyd_arch}" /usr/local/bin/ttyd
  fi
}

load_container_images() {
  if [ ! -d "${IMAGE_DIR}" ] || ! compgen -G "${IMAGE_DIR}/*.tar" >/dev/null; then
    return
  fi
  if command -v docker >/dev/null 2>&1; then
    mkdir -p "${STATE_DIR}/images"
    systemctl start docker >/dev/null 2>&1 || true
    for image_tar in "${IMAGE_DIR}"/*.tar; do
      local checksum marker
      checksum="$(sha256sum "${image_tar}" | awk '{print $1}')"
      marker="${STATE_DIR}/images/$(basename "${image_tar}").sha256"
      if [ "$(cat "${marker}" 2>/dev/null || true)" = "${checksum}" ]; then
        info "Container image already loaded from ${image_tar}; skipping."
        continue
      fi
      info "Loading container image ${image_tar}"
      docker load -i "${image_tar}"
      printf '%s\n' "${checksum}" > "${marker}"
    done
  else
    warn "Docker is not installed yet; bundled image tarballs remain in ${IMAGE_DIR}."
  fi
}

configure_language_package_caches() {
  if [ -d "${NPM_CACHE_DIR}" ]; then
    info "Configuring npm to prefer bundled cache"
    touch /etc/npmrc
    local npmrc_tmp
    npmrc_tmp="$(mktemp)"
    awk -F= '$1 != "cache" && $1 != "prefer-offline" { print }' /etc/npmrc > "${npmrc_tmp}"
    printf 'cache=%s\nprefer-offline=true\n' "${NPM_CACHE_DIR}" >> "${npmrc_tmp}"
    install -m 0644 "${npmrc_tmp}" /etc/npmrc
    rm -f "${npmrc_tmp}"
    if command -v npm >/dev/null 2>&1; then
      npm config set cache "${NPM_CACHE_DIR}" --global || true
      npm config set prefer-offline true --global || true
    fi
  fi

  if [ -d "${PIP_WHEEL_DIR}" ]; then
    info "Configuring pip to prefer bundled wheelhouse"
    export PIP_FIND_LINKS="${PIP_WHEEL_DIR}"
    export PIP_PREFER_BINARY=true
    if command -v python3 >/dev/null 2>&1 &&
       python3 -m pip --version >/dev/null 2>&1; then
      python3 -m pip config --global set global.find-links "${PIP_WHEEL_DIR}"
      python3 -m pip config --global set global.prefer-binary true
    fi
  fi
}

run_bootstrap() {
  local setup_script="${ROOT}/repos/xworkspace-console/scripts/setup-ai-workspace-all-in-one.sh"
  if [ ! -x "${setup_script}" ]; then
    chmod +x "${setup_script}"
  fi

  export PLAYBOOK_DIR="${PLAYBOOK_DIR:-${ROOT}/repos/playbooks}"
  export XWORKSPACE_CONSOLE_DIR="${XWORKSPACE_CONSOLE_DIR:-${ROOT}/repos/xworkspace-console}"
  export XWORKSPACE_CORE_SKILLS_DIR="${XWORKSPACE_CORE_SKILLS_DIR:-${ROOT}/repos/xworkspace-core-skills}"
  export XWORKMATE_BRIDGE_SOURCE_DIR="${XWORKMATE_BRIDGE_SOURCE_DIR:-${ROOT}/repos/xworkmate-bridge}"
  export QMD_SOURCE_REPO="${QMD_SOURCE_REPO:-file://${ROOT}/repos/qmd}"
  export LITELLM_SOURCE_REPO="${LITELLM_SOURCE_REPO:-file://${ROOT}/repos/litellm}"
  export XWORKSPACE_CONSOLE_PUBLIC_ACCESS="${XWORKSPACE_CONSOLE_PUBLIC_ACCESS:-false}"
  export XWORKMATE_BRIDGE_PUBLIC_ACCESS="${XWORKMATE_BRIDGE_PUBLIC_ACCESS:-true}"
  export GATEWAY_OPENCLAW_PUBLIC_ACCESS="${GATEWAY_OPENCLAW_PUBLIC_ACCESS:-false}"
  export VAULT_PUBLIC_ACCESS="${VAULT_PUBLIC_ACCESS:-false}"
  export AI_WORKSPACE_OFFLINE_ACTIVE=true
  export AI_WORKSPACE_DEPLOYMENT_LOCK_HELD=true
  export AI_WORKSPACE_APT_LOCK_TIMEOUT

  info "Running packaged AI Workspace all-in-one bootstrap"
  bash "${setup_script}"
}

main() {
  require_root
  acquire_deployment_lock
  wait_for_apt_locks
  configure_local_apt_repo
  install_offline_prerequisites
  install_bundled_binaries
  load_container_images
  configure_language_package_caches
  run_bootstrap
}

main "$@"
