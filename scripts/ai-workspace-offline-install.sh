#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APT_DIR="${ROOT}/packages/apt"
BIN_DIR="${ROOT}/packages/bin"
IMAGE_DIR="${ROOT}/packages/images"
NPM_CACHE_DIR="${ROOT}/packages/npm-cache"
PIP_WHEEL_DIR="${ROOT}/packages/pip"

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

configure_local_apt_repo() {
  if [ ! -d "${APT_DIR}" ] || ! compgen -G "${APT_DIR}/*.deb" >/dev/null; then
    warn "No offline .deb cache found at ${APT_DIR}; skipping local APT repo setup."
    return
  fi

  info "Configuring local APT repository from ${APT_DIR}"
  cat > /etc/apt/sources.list.d/ai-workspace-offline.list <<EOF
deb [trusted=yes] file:${APT_DIR} ./
EOF
  apt-get update -o Dir::Etc::sourcelist="sources.list.d/ai-workspace-offline.list" \
    -o Dir::Etc::sourceparts="-" \
    -o APT::Get::List-Cleanup="0"
}

install_bundled_binaries() {
  if compgen -G "${BIN_DIR}/vault_*_linux_*.zip" >/dev/null; then
    info "Installing bundled Vault binary"
    apt-get install -y unzip || true
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
    for image_tar in "${IMAGE_DIR}"/*.tar; do
      info "Loading container image ${image_tar}"
      docker load -i "${image_tar}" || true
    done
  else
    warn "Docker is not installed yet; bundled image tarballs remain in ${IMAGE_DIR}."
  fi
}

configure_language_package_caches() {
  if [ -d "${NPM_CACHE_DIR}" ]; then
    info "Configuring npm to prefer bundled cache"
    npm config set cache "${NPM_CACHE_DIR}" --global || true
    npm config set prefer-offline true --global || true
  fi

  if [ -d "${PIP_WHEEL_DIR}" ]; then
    info "Configuring pip to prefer bundled wheelhouse"
    mkdir -p /etc/pip.conf.d
    cat > /etc/pip.conf <<EOF
[global]
find-links = ${PIP_WHEEL_DIR}
prefer-binary = true
EOF
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

  info "Running packaged AI Workspace all-in-one bootstrap"
  bash "${setup_script}"
}

main() {
  require_root
  configure_local_apt_repo
  install_bundled_binaries
  load_container_images
  configure_language_package_caches
  run_bootstrap
}

main "$@"
