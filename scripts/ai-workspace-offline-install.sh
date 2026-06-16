#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "${ROOT}/metadata/target.env" ]; then
  # shellcheck disable=SC1091
  source "${ROOT}/metadata/target.env"
fi
APT_DIR="${ROOT}/packages/apt"
BIN_DIR="${ROOT}/packages/bin"
COMPONENT_DIR="${ROOT}/packages/components"
TARGET_ARCH="${ARCH:-}"
CONSOLE_RUNTIME_ASSET="${COMPONENT_DIR}/xworkspace-console-runtime-linux-${TARGET_ARCH}.tar.gz"
BRIDGE_RUNTIME_ASSET="${COMPONENT_DIR}/xworkmate-bridge-linux-${TARGET_ARCH}.tar.gz"
QMD_RUNTIME_ASSET="${COMPONENT_DIR}/qmd-runtime-linux-${TARGET_ARCH}.tar.gz"
LITELLM_RUNTIME_ASSET="${COMPONENT_DIR}/litellm-runtime-${DISTRO_ID:-}-${DISTRO_VERSION:-}-${TARGET_ARCH}.tar.gz"
IMAGE_DIR="${ROOT}/packages/images"
NPM_CACHE_DIR="${ROOT}/packages/npm-cache"
NPM_RUNTIME_CACHE_DIR="${AI_WORKSPACE_NPM_CACHE_DIR:-/var/cache/ai-workspace/npm}"
PIP_WHEEL_DIR="${ROOT}/packages/pip"
PLAYWRIGHT_BROWSER_DIR="${ROOT}/packages/playwright-browsers"
PLAYWRIGHT_BROWSER_INSTALL_DIR="${AI_WORKSPACE_PLAYWRIGHT_BROWSER_DIR:-/opt/ai-workspace/playwright-browsers}"
PORTABLE_PYTHON_DIR="${ROOT}/packages/python"
PORTABLE_PYTHON_INSTALL_DIR="${AI_WORKSPACE_PORTABLE_PYTHON_DIR:-/opt/ai-workspace/python}"
STATE_DIR="${AI_WORKSPACE_OFFLINE_STATE_DIR:-/var/lib/ai-workspace/offline}"
AI_WORKSPACE_DEPLOYMENT_LOCK_TIMEOUT="${AI_WORKSPACE_DEPLOYMENT_LOCK_TIMEOUT:-1800}"
AI_WORKSPACE_APT_LOCK_TIMEOUT="${AI_WORKSPACE_APT_LOCK_TIMEOUT:-900}"
APT_SOURCE_FILE="/etc/apt/sources.list.d/ai-workspace-offline.list"
APT_CONFIG_FILE="/etc/apt/apt.conf.d/99ai-workspace-offline"
BROWSER_APT_PACKAGE_FILE="${ROOT}/metadata/apt/browser-deb-packages.txt"
SAFE_GIT_DIRS=()
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

cleanup() {
  rm -f "${APT_SOURCE_FILE}" "${APT_CONFIG_FILE}"
  local git_dir
  for git_dir in "${SAFE_GIT_DIRS[@]}"; do
    git config --system --unset-all safe.directory "${git_dir}" >/dev/null 2>&1 || true
  done
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
  cat > "${APT_CONFIG_FILE}" <<'EOF'
Dir::Etc::sourcelist "sources.list.d/ai-workspace-offline.list";
Dir::Etc::sourceparts "-";
APT::Get::List-Cleanup "0";
Acquire::Languages "none";
EOF
  apt-get "${APT_LOCAL_OPTIONS[@]}" update
}

configure_local_git_sources() {
  local repo_dir
  for repo_dir in \
    "${ROOT}/repos/xworkspace-console" \
    "${ROOT}/repos/xworkspace-core-skills" \
    "${ROOT}/repos/xworkmate-bridge" \
    "${ROOT}/repos/playbooks"; do
    [ -d "${repo_dir}/.git" ] || continue
    if ! git config --system --get-all safe.directory 2>/dev/null | grep -Fxq "${repo_dir}"; then
      git config --system --add safe.directory "${repo_dir}"
      SAFE_GIT_DIRS+=("${repo_dir}")
    fi
  done
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
  local browser_package

  if [ -d "${PLAYWRIGHT_BROWSER_DIR}" ] && [ ! -s "${BROWSER_APT_PACKAGE_FILE}" ]; then
    echo "Bundled Playwright Chromium dependency manifest is missing." >&2
    exit 1
  fi
  if [ -d "${PLAYWRIGHT_BROWSER_DIR}" ]; then
    while IFS= read -r browser_package; do
      [ -n "${browser_package}" ] && packages+=("${browser_package}")
    done < "${BROWSER_APT_PACKAGE_FILE}"
  fi

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

  if [ -f "${BRIDGE_RUNTIME_ASSET}" ]; then
    local bridge_extract
    bridge_extract="$(mktemp -d)"
    tar -xzf "${BRIDGE_RUNTIME_ASSET}" -C "${bridge_extract}"
    install -m 0755 "${bridge_extract}/xworkmate-bridge/bin/xworkmate-go-core" \
      "${BIN_DIR}/xworkmate-go-core.${TARGET_ARCH}"
    rm -rf "${bridge_extract}"
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

  case "$(uname -m)" in
    x86_64|amd64) bridge_arch=amd64 ;;
    aarch64|arm64) bridge_arch=arm64 ;;
    *) bridge_arch="" ;;
  esac
  if [ -n "${bridge_arch}" ] && [ -f "${BIN_DIR}/xworkmate-go-core.${bridge_arch}" ]; then
    info "Installing bundled XWorkmate Bridge binary"
    local bridge_immutable=false
    if command -v lsattr >/dev/null 2>&1 &&
       lsattr /usr/local/bin/xworkmate-go-core 2>/dev/null | awk '{print $1}' | grep -q 'i'; then
      bridge_immutable=true
      chattr -i /usr/local/bin/xworkmate-go-core
    fi
    install -m 0755 "${BIN_DIR}/xworkmate-go-core.${bridge_arch}" /usr/local/bin/xworkmate-go-core
    if [ "${bridge_immutable}" = "true" ]; then
      chattr +i /usr/local/bin/xworkmate-go-core
    fi
  fi
}

install_bundled_playwright_browser() {
  if [ ! -d "${PLAYWRIGHT_BROWSER_DIR}" ]; then
    return
  fi

  local seed_checksum marker browser_binary
  seed_checksum="$(sha256sum "${ROOT}/metadata/manifest.json" | awk '{print $1}')"
  marker="${PLAYWRIGHT_BROWSER_INSTALL_DIR}/.ai-workspace-seed-sha256"
  if [ "$(cat "${marker}" 2>/dev/null || true)" != "${seed_checksum}" ]; then
    info "Installing bundled Playwright Chromium runtime"
    rm -rf "${PLAYWRIGHT_BROWSER_INSTALL_DIR}"
    mkdir -p "${PLAYWRIGHT_BROWSER_INSTALL_DIR}"
    cp -a "${PLAYWRIGHT_BROWSER_DIR}/." "${PLAYWRIGHT_BROWSER_INSTALL_DIR}/"
    printf '%s\n' "${seed_checksum}" > "${marker}"
  else
    info "Reusing bundled Playwright Chromium runtime"
  fi

  chown -R root:root "${PLAYWRIGHT_BROWSER_INSTALL_DIR}"
  chmod -R a+rX "${PLAYWRIGHT_BROWSER_INSTALL_DIR}"
  browser_binary="$(
    find "${PLAYWRIGHT_BROWSER_INSTALL_DIR}" -type f \
      \( -path '*/chrome-linux/chrome' -o -path '*/chrome-linux64/chrome' \) \
      -print -quit
  )"
  if [ -z "${browser_binary}" ] || [ ! -x "${browser_binary}" ]; then
    echo "Bundled Playwright Chromium executable is missing." >&2
    exit 1
  fi
  ln -sfn "${browser_binary}" /usr/local/bin/chromium
}

install_bundled_python_runtime() {
  local packaged_python installed_python marker seed_checksum
  packaged_python="$(
    find -L "${PORTABLE_PYTHON_DIR}" -type f -path '*/bin/python3.13' -perm /111 -print -quit 2>/dev/null || true
  )"
  if [ -z "${packaged_python}" ]; then
    return
  fi

  seed_checksum="$(sha256sum "${ROOT}/metadata/manifest.json" | awk '{print $1}')"
  marker="${PORTABLE_PYTHON_INSTALL_DIR}/.ai-workspace-seed-sha256"
  if [ "$(cat "${marker}" 2>/dev/null || true)" != "${seed_checksum}" ]; then
    info "Installing bundled portable Python runtime"
    rm -rf "${PORTABLE_PYTHON_INSTALL_DIR}"
    mkdir -p "${PORTABLE_PYTHON_INSTALL_DIR}"
    cp -a "${PORTABLE_PYTHON_DIR}/." "${PORTABLE_PYTHON_INSTALL_DIR}/"
    printf '%s\n' "${seed_checksum}" > "${marker}"
  else
    info "Reusing bundled portable Python runtime"
  fi

  chown -R root:root "${PORTABLE_PYTHON_INSTALL_DIR}"
  chmod -R a+rX "${PORTABLE_PYTHON_INSTALL_DIR}"
  installed_python="$(
    find -L "${PORTABLE_PYTHON_INSTALL_DIR}" -type f -path '*/bin/python3.13' -perm /111 -print -quit
  )"
  if [ -z "${installed_python}" ]; then
    echo "Installed portable Python executable is missing." >&2
    exit 1
  fi
  ln -sfn "${installed_python}" /usr/local/bin/ai-workspace-python
  cat > /usr/local/bin/ai-workspace-pip <<'EOF'
#!/usr/bin/env bash
exec /usr/local/bin/ai-workspace-python -m pip "$@"
EOF
  chmod 0755 /usr/local/bin/ai-workspace-pip
  export LITELLM_PYTHON_EXECUTABLE=/usr/local/bin/ai-workspace-python
  export LITELLM_PIP_EXECUTABLE=/usr/local/bin/ai-workspace-pip
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
    local cache_group="ai-workspace-cache"
    local cache_user="${AI_WORKSPACE_RUNTIME_USER:-ubuntu}"
    local seed_checksum marker

    getent group "${cache_group}" >/dev/null 2>&1 || groupadd --system "${cache_group}"
    if [ "${cache_user}" != "root" ] && ! id "${cache_user}" >/dev/null 2>&1; then
      useradd --create-home --shell /bin/bash "${cache_user}"
    fi
    if [ "${cache_user}" != "root" ]; then
      usermod --append --groups "${cache_group}" "${cache_user}"
    fi

    seed_checksum="$(sha256sum "${ROOT}/metadata/manifest.json" | awk '{print $1}')"
    marker="${NPM_RUNTIME_CACHE_DIR}/.ai-workspace-seed-sha256"
    if [ "$(cat "${marker}" 2>/dev/null || true)" != "${seed_checksum}" ]; then
      info "Seeding shared npm cache from the offline package"
      rm -rf "${NPM_RUNTIME_CACHE_DIR}"
      mkdir -p "${NPM_RUNTIME_CACHE_DIR}"
      cp -a "${NPM_CACHE_DIR}/." "${NPM_RUNTIME_CACHE_DIR}/"
      printf '%s\n' "${seed_checksum}" > "${marker}"
    else
      info "Reusing shared npm cache at ${NPM_RUNTIME_CACHE_DIR}"
    fi
    chown -R "root:${cache_group}" "${NPM_RUNTIME_CACHE_DIR}"
    find "${NPM_RUNTIME_CACHE_DIR}" -type d -exec chmod 2770 {} +
    find "${NPM_RUNTIME_CACHE_DIR}" -type f -exec chmod 0660 {} +

    info "Configuring npm to prefer bundled cache"
    touch /etc/npmrc
    local npmrc_tmp
    npmrc_tmp="$(mktemp)"
    awk -F= '$1 != "cache" && $1 != "prefer-offline" { print }' /etc/npmrc > "${npmrc_tmp}"
    printf 'cache=%s\nprefer-offline=true\n' "${NPM_RUNTIME_CACHE_DIR}" >> "${npmrc_tmp}"
    install -m 0644 "${npmrc_tmp}" /etc/npmrc
    rm -f "${npmrc_tmp}"
    if command -v npm >/dev/null 2>&1; then
      npm config set cache "${NPM_RUNTIME_CACHE_DIR}" --global || true
      npm config set prefer-offline true --global || true
    fi
  fi

  if [ -d "${PIP_WHEEL_DIR}" ]; then
    info "Configuring pip to prefer bundled wheelhouse"
    export PIP_FIND_LINKS="${PIP_WHEEL_DIR}"
    export PIP_PREFER_BINARY=true
    export PIP_NO_INDEX=true
    if command -v python3 >/dev/null 2>&1 &&
       python3 -m pip --version >/dev/null 2>&1; then
      python3 -m pip config --global set global.find-links "${PIP_WHEEL_DIR}"
      python3 -m pip config --global set global.prefer-binary true
      python3 -m pip config --global set global.no-index true
    fi
  elif [ "${AI_WORKSPACE_PREBUILT_COMPONENTS_REQUIRED:-true}" = "true" ]; then
    echo "Bundled LiteLLM wheelhouse is required but missing: ${PIP_WHEEL_DIR}" >&2
    exit 1
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
  export XWORKSPACE_CONSOLE_RUNTIME_ARCHIVE="${XWORKSPACE_CONSOLE_RUNTIME_ARCHIVE:-${CONSOLE_RUNTIME_ASSET}}"
  export QMD_RUNTIME_ARCHIVE="${QMD_RUNTIME_ARCHIVE:-${QMD_RUNTIME_ASSET}}"
  [ -f "${LITELLM_RUNTIME_ASSET}" ] ||
    { echo "Exact LiteLLM runtime asset is missing: ${LITELLM_RUNTIME_ASSET}" >&2; exit 1; }
  if [ -f "${ROOT}/metadata/litellm-runtime.env" ]; then
    # shellcheck disable=SC1091
    source "${ROOT}/metadata/litellm-runtime.env"
    export LITELLM_PACKAGE_SPEC
  fi
  export XWORKSPACE_CONSOLE_PUBLIC_ACCESS="${XWORKSPACE_CONSOLE_PUBLIC_ACCESS:-false}"
  export XWORKMATE_BRIDGE_PUBLIC_ACCESS="${XWORKMATE_BRIDGE_PUBLIC_ACCESS:-true}"
  export GATEWAY_OPENCLAW_PUBLIC_ACCESS="${GATEWAY_OPENCLAW_PUBLIC_ACCESS:-false}"
  export VAULT_PUBLIC_ACCESS="${VAULT_PUBLIC_ACCESS:-false}"
  export AI_WORKSPACE_OFFLINE_ACTIVE=true
  export AI_WORKSPACE_PREBUILT_COMPONENTS_REQUIRED=true
  export AI_WORKSPACE_USE_PREBUILT_BRIDGE=true
  export AI_WORKSPACE_RUNTIME_PREBUILD_ENABLED=false
  export AI_WORKSPACE_DEPLOYMENT_LOCK_HELD=true
  export AI_WORKSPACE_APT_LOCK_TIMEOUT

  info "Running packaged AI Workspace all-in-one bootstrap"
  bash "${setup_script}"
}

main() {
  require_root
  trap cleanup EXIT
  acquire_deployment_lock
  wait_for_apt_locks
  configure_local_apt_repo
  install_offline_prerequisites
  configure_local_git_sources
  install_bundled_binaries
  install_bundled_playwright_browser
  install_bundled_python_runtime
  load_container_images
  configure_language_package_caches
  run_bootstrap
}

main "$@"
