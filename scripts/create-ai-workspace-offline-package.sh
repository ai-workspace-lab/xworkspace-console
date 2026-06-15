#!/usr/bin/env bash
set -euo pipefail

DISTRO_ID="${DISTRO_ID:?DISTRO_ID is required, e.g. debian or ubuntu}"
DISTRO_VERSION="${DISTRO_VERSION:?DISTRO_VERSION is required, e.g. 13 or 24.04}"
ARCH="${ARCH:-amd64}"
PACKAGE_VERSION="${PACKAGE_VERSION:-$(date -u +%Y%m%d%H%M%S)}"

PLAYBOOKS_REPO="${PLAYBOOKS_REPO:-https://github.com/ai-workspace-infra/playbooks.git}"
PLAYBOOKS_REF="${PLAYBOOKS_REF:-main}"
CONSOLE_REPO="${CONSOLE_REPO:-https://github.com/ai-workspace-lab/xworkspace-console.git}"
CONSOLE_REF="${CONSOLE_REF:-main}"
CORE_SKILLS_REPO="${CORE_SKILLS_REPO:-https://github.com/ai-workspace-lab/xworkspace-core-skills.git}"
CORE_SKILLS_REF="${CORE_SKILLS_REF:-main}"
XWORKMATE_BRIDGE_REPO="${XWORKMATE_BRIDGE_REPO:-https://github.com/ai-workspace-lab/xworkmate-bridge.git}"
XWORKMATE_BRIDGE_REF="${XWORKMATE_BRIDGE_REF:-release/v1.1.4}"
QMD_REPO="${QMD_REPO:-https://github.com/ai-workspace-services/qmd.git}"
QMD_REF="${QMD_REF:-main}"
LITELLM_REPO="${LITELLM_REPO:-https://github.com/ai-workspace-services/litellm.git}"
LITELLM_REF="${LITELLM_REF:-litellm_internal_staging}"

NODEJS_MAJOR_VERSIONS="${NODEJS_MAJOR_VERSIONS:-22 24}"
NODEJS_22_VERSION="${NODEJS_22_VERSION:-22.22.3}"
NODEJS_24_VERSION="${NODEJS_24_VERSION:-24.16.0}"
VAULT_VERSION="${VAULT_VERSION:-1.21.4}"
TTYD_VERSION="${TTYD_VERSION:-latest}"
POSTGRES_IMAGE="${POSTGRES_IMAGE:-postgres:17.7}"
OPENCLAW_VERSION="${OPENCLAW_VERSION:-2026.6.6}"
PLAYWRIGHT_VERSION="${PLAYWRIGHT_VERSION:-1.60.0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

case "${ARCH}" in
  x86_64|amd64) ARCH=amd64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  *) echo "Unsupported ARCH: ${ARCH}" >&2; exit 1 ;;
esac

case "${DISTRO_ID}:${DISTRO_VERSION}" in
  debian:11|debian:12|debian:13|ubuntu:22.04|ubuntu:24.04|ubuntu:26.04) ;;
  *)
    echo "Unsupported target: ${DISTRO_ID}:${DISTRO_VERSION}" >&2
    echo "Supported: debian 11/12/13 and ubuntu 22.04/24.04/26.04" >&2
    exit 1
    ;;
esac

WORKDIR="${WORKDIR:-${REPO_ROOT}/ai-workspace-all-in-one-offline-${DISTRO_ID}-${DISTRO_VERSION}-${ARCH}}"
OUT="${OUT:-${REPO_ROOT}/ai-workspace-all-in-one-offline-${DISTRO_ID}-${DISTRO_VERSION}-${ARCH}.tar.gz}"

image_for_target() {
  case "${DISTRO_ID}" in
    debian) echo "debian:${DISTRO_VERSION}" ;;
    ubuntu) echo "ubuntu:${DISTRO_VERSION}" ;;
  esac
}

safe_name() {
  tr '/:@+' '----' <<<"$1"
}

clone_repo() {
  local url=$1
  local ref=$2
  local dest=$3

  git clone --depth 1 --branch "${ref}" "${url}" "${dest}" 2>/dev/null || {
    git clone --depth 1 "${url}" "${dest}"
    git -C "${dest}" fetch --depth 1 origin "${ref}"
    git -C "${dest}" checkout FETCH_HEAD
  }
  git -C "${dest}" rev-parse HEAD
}

download_apt_packages() {
  local image=$1
  local platform="linux/${ARCH}"
  local apt_dir="${WORKDIR}/packages/apt"
  local apt_lists="${WORKDIR}/metadata/apt"

  mkdir -p "${apt_dir}" "${apt_lists}"

  docker run --rm --platform "${platform}" \
    -e DISTRO_ID="${DISTRO_ID}" \
    -e NODEJS_MAJOR_VERSIONS="${NODEJS_MAJOR_VERSIONS}" \
    -e NODEJS_22_VERSION="${NODEJS_22_VERSION}" \
    -e NODEJS_24_VERSION="${NODEJS_24_VERSION}" \
    -v "${apt_dir}:/offline-apt" \
    -v "${apt_lists}:/offline-meta" \
    "${image}" \
    bash -lc "$(cat <<'CONTAINER'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y ca-certificates curl gnupg dpkg-dev apt-transport-https

install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key -o /etc/apt/keyrings/nodesource.gpg
for major in ${NODEJS_MAJOR_VERSIONS}; do
  echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${major}.x nodistro main" \
    > "/etc/apt/sources.list.d/nodesource-node${major}.list"
done
curl -fsSL https://dl.google.com/linux/linux_signing_key.pub \
  | gpg --dearmor -o /etc/apt/keyrings/google-linux-signing-key.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/google-linux-signing-key.gpg] https://dl.google.com/linux/chrome/deb/ stable main" \
  > /etc/apt/sources.list.d/google-chrome.list
curl -fsSL https://dl.yarnpkg.com/debian/pubkey.gpg -o /etc/apt/keyrings/yarn.asc
echo "deb [signed-by=/etc/apt/keyrings/yarn.asc] https://dl.yarnpkg.com/debian/ stable main" \
  > /etc/apt/sources.list.d/yarn.list
curl -fsSL https://download.docker.com/linux/${DISTRO_ID}/gpg -o /etc/apt/keyrings/docker.asc || true
if [ "${DISTRO_ID}" = "ubuntu" ] || [ "${DISTRO_ID}" = "debian" ]; then
  . /etc/os-release
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${DISTRO_ID} ${VERSION_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
fi

apt-get update -y || true

required_packages=(
  ansible git curl ca-certificates gnupg jq rsync unzip wget
)
optional_packages=(
  caddy xfce4 python3 python3-pip python3-venv python3-dev python3-setuptools
  build-essential pkg-config python-is-python3 pandoc fonts-noto-cjk
  fonts-noto-cjk-extra fonts-wqy-zenhei fonts-wqy-microhei
  google-chrome-stable nodejs yarn
)
packages=()

for package in "${required_packages[@]}"; do
  if ! apt-cache show "${package}" >/dev/null 2>&1; then
    echo "Required APT package is unavailable for this target: ${package}" >&2
    exit 1
  fi
  packages+=("${package}")
done

for package in "${optional_packages[@]}"; do
  if apt-cache show "${package}" >/dev/null 2>&1; then
    packages+=("${package}")
  else
    echo "Skipping unavailable optional APT package: ${package}" >&2
  fi
done

if apt-cache show docker-ce >/dev/null 2>&1; then
  packages+=(docker-ce docker-ce-cli containerd.io)
  for package in docker-buildx-plugin docker-compose-plugin; do
    if apt-cache show "${package}" >/dev/null 2>&1; then
      packages+=("${package}")
    fi
  done
elif apt-cache show docker.io >/dev/null 2>&1; then
  packages+=(docker.io)
  if apt-cache show docker-compose-plugin >/dev/null 2>&1; then
    packages+=(docker-compose-plugin)
  fi
fi

if apt-cache show golang-go >/dev/null 2>&1; then
  packages+=(golang-go)
fi
if apt-cache show texlive-xetex >/dev/null 2>&1; then
  packages+=(texlive-xetex texlive-latex-extra texlive-fonts-recommended texlive-lang-chinese latexmk)
fi

apt-get install --download-only -y --no-install-recommends "${packages[@]}"
apt-get download "nodejs=${NODEJS_22_VERSION}-1nodesource1" || true
apt-get download "nodejs=${NODEJS_24_VERSION}-1nodesource1" || true
cp -n ./*.deb /offline-apt/ 2>/dev/null || true
find /var/cache/apt/archives -name '*.deb' -exec cp -n {} /offline-apt/ \;
cd /offline-apt
dpkg-scanpackages . /dev/null | gzip -9c > Packages.gz
find . -maxdepth 1 -name '*.deb' -printf '%f\n' | sort > /offline-meta/deb-files.txt
CONTAINER
)" \
    -e DISTRO_ID="${DISTRO_ID}" \
    -e NODEJS_MAJOR_VERSIONS="${NODEJS_MAJOR_VERSIONS}"
}

download_npm_packages() {
  local npm_dir="${WORKDIR}/packages/npm"
  local npm_cache_dir="${WORKDIR}/packages/npm-cache"
  mkdir -p "${npm_dir}" "${npm_cache_dir}"
  npm pack --pack-destination "${npm_dir}" "opencode-ai"
  npm pack --pack-destination "${npm_dir}" "@google/gemini-cli"
  npm pack --pack-destination "${npm_dir}" "@openai/codex"
  npm pack --pack-destination "${npm_dir}" "@anthropic-ai/claude-code"
  npm pack --pack-destination "${npm_dir}" "openclaw@${OPENCLAW_VERSION}"
  npm pack --pack-destination "${npm_dir}" "@openclaw/codex@${OPENCLAW_VERSION}"
  npm pack --pack-destination "${npm_dir}" "playwright@${PLAYWRIGHT_VERSION}"
  npm cache add --cache "${npm_cache_dir}" "opencode-ai"
  npm cache add --cache "${npm_cache_dir}" "@google/gemini-cli"
  npm cache add --cache "${npm_cache_dir}" "@openai/codex"
  npm cache add --cache "${npm_cache_dir}" "@anthropic-ai/claude-code"
  npm cache add --cache "${npm_cache_dir}" "openclaw@${OPENCLAW_VERSION}"
  npm cache add --cache "${npm_cache_dir}" "@openclaw/codex@${OPENCLAW_VERSION}"
  npm cache add --cache "${npm_cache_dir}" "playwright@${PLAYWRIGHT_VERSION}"
}

download_pip_wheels() {
  local wheel_dir="${WORKDIR}/packages/pip"
  mkdir -p "${wheel_dir}"
  python3 -m pip download --dest "${wheel_dir}" \
    "litellm[proxy] @ git+${LITELLM_REPO}@${LITELLM_REF}" \
    prisma psycopg2-binary || true
}

download_binaries() {
  local bin_dir="${WORKDIR}/packages/bin"
  local vault_arch="${ARCH}"
  local ttyd_arch
  mkdir -p "${bin_dir}"

  case "${ARCH}" in
    amd64) ttyd_arch=x86_64 ;;
    arm64) ttyd_arch=aarch64 ;;
  esac

  curl -fsSL \
    "https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_${vault_arch}.zip" \
    -o "${bin_dir}/vault_${VAULT_VERSION}_linux_${vault_arch}.zip"

  if [ "${TTYD_VERSION}" = "latest" ]; then
    curl -fsSL "https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.${ttyd_arch}" \
      -o "${bin_dir}/ttyd.${ttyd_arch}"
  else
    curl -fsSL "https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/ttyd.${ttyd_arch}" \
      -o "${bin_dir}/ttyd.${ttyd_arch}"
  fi
  chmod +x "${bin_dir}/ttyd.${ttyd_arch}"
}

export_container_images() {
  local images_dir="${WORKDIR}/packages/images"
  mkdir -p "${images_dir}"
  docker pull --platform "linux/${ARCH}" "${POSTGRES_IMAGE}"
  docker save "${POSTGRES_IMAGE}" -o "${images_dir}/$(safe_name "${POSTGRES_IMAGE}").tar"
}

write_manifest() {
  local manifest="${WORKDIR}/metadata/manifest.json"
  mkdir -p "$(dirname "${manifest}")"
  cat > "${WORKDIR}/metadata/target.env" <<EOF
DISTRO_ID=${DISTRO_ID}
DISTRO_VERSION=${DISTRO_VERSION}
ARCH=${ARCH}
EOF
  cat > "${manifest}" <<JSON
{
  "name": "ai-workspace-all-in-one-offline",
  "packageVersion": "${PACKAGE_VERSION}",
  "target": {
    "distro": "${DISTRO_ID}",
    "version": "${DISTRO_VERSION}",
    "arch": "${ARCH}"
  },
  "sources": {
    "playbooks": {"repo": "${PLAYBOOKS_REPO}", "ref": "${PLAYBOOKS_REF}"},
    "xworkspaceConsole": {"repo": "${CONSOLE_REPO}", "ref": "${CONSOLE_REF}"},
    "xworkspaceCoreSkills": {"repo": "${CORE_SKILLS_REPO}", "ref": "${CORE_SKILLS_REF}"},
    "xworkmateBridge": {"repo": "${XWORKMATE_BRIDGE_REPO}", "ref": "${XWORKMATE_BRIDGE_REF}"},
    "qmd": {"repo": "${QMD_REPO}", "ref": "${QMD_REF}"},
    "litellm": {"repo": "${LITELLM_REPO}", "ref": "${LITELLM_REF}"}
  },
  "versions": {
    "vault": "${VAULT_VERSION}",
    "openclaw": "${OPENCLAW_VERSION}",
    "playwright": "${PLAYWRIGHT_VERSION}",
    "postgresImage": "${POSTGRES_IMAGE}"
  }
}
JSON
}

main() {
  rm -rf "${WORKDIR}" "${OUT}"
  mkdir -p "${WORKDIR}/repos" "${WORKDIR}/scripts" "${WORKDIR}/metadata"

  local image
  image="$(image_for_target)"

  echo "Building AI Workspace offline package for ${DISTRO_ID} ${DISTRO_VERSION} ${ARCH}"
  echo "Using package workspace: ${WORKDIR}"

  clone_repo "${PLAYBOOKS_REPO}" "${PLAYBOOKS_REF}" "${WORKDIR}/repos/playbooks" > "${WORKDIR}/metadata/playbooks.commit"
  clone_repo "${CONSOLE_REPO}" "${CONSOLE_REF}" "${WORKDIR}/repos/xworkspace-console" > "${WORKDIR}/metadata/xworkspace-console.commit"
  clone_repo "${CORE_SKILLS_REPO}" "${CORE_SKILLS_REF}" "${WORKDIR}/repos/xworkspace-core-skills" > "${WORKDIR}/metadata/xworkspace-core-skills.commit"
  clone_repo "${XWORKMATE_BRIDGE_REPO}" "${XWORKMATE_BRIDGE_REF}" "${WORKDIR}/repos/xworkmate-bridge" > "${WORKDIR}/metadata/xworkmate-bridge.commit"
  clone_repo "${QMD_REPO}" "${QMD_REF}" "${WORKDIR}/repos/qmd" > "${WORKDIR}/metadata/qmd.commit"
  clone_repo "${LITELLM_REPO}" "${LITELLM_REF}" "${WORKDIR}/repos/litellm" > "${WORKDIR}/metadata/litellm.commit"

  download_apt_packages "${image}"
  download_npm_packages
  download_pip_wheels
  download_binaries
  export_container_images

  cp "${SCRIPT_DIR}/ai-workspace-offline-install.sh" "${WORKDIR}/scripts/"
  chmod +x "${WORKDIR}/scripts/ai-workspace-offline-install.sh"
  write_manifest

  cat > "${WORKDIR}/README.md" <<'README'
# AI Workspace All-in-One Offline Package

The standard online bootstrap can use matching packages published from
`https://github.com/ai-workspace-lab/xworkspace-console/releases` automatically:

```bash
curl -sfL https://raw.githubusercontent.com/ai-workspace-lab/xworkspace-console/main/scripts/setup-ai-workspace-all-in-one.sh | bash -
```

Extract this archive on the target host, then run:

```bash
sudo ./scripts/ai-workspace-offline-install.sh
```

The installer configures a local APT repository from `packages/apt`, loads bundled
container images when Docker is available, and runs the packaged
`xworkspace-console/scripts/setup-ai-workspace-all-in-one.sh` with local source
directories for playbooks, console, core skills, and bridge code.

Set the same environment variables supported by the online installer before
running the script, for example:

```bash
sudo env \
  XWORKMATE_BRIDGE_DOMAIN=acp-bridge.onwalk.net \
  AI_WORKSPACE_SECURITY_LEVEL=strict \
  ./scripts/ai-workspace-offline-install.sh
```
README

  tar -czf "${OUT}" -C "$(dirname "${WORKDIR}")" "$(basename "${WORKDIR}")"
  ls -lh "${OUT}"
}

main "$@"
