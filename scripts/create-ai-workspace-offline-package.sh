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
LITELLM_DEBIAN_11_VERSION="${LITELLM_DEBIAN_11_VERSION:-1.74.9}"

NODEJS_MAJOR_VERSIONS="${NODEJS_MAJOR_VERSIONS:-22 24}"
NODEJS_22_VERSION="${NODEJS_22_VERSION:-22.22.3}"
NODEJS_24_VERSION="${NODEJS_24_VERSION:-24.16.0}"
VAULT_VERSION="${VAULT_VERSION:-1.21.4}"
TTYD_VERSION="${TTYD_VERSION:-latest}"
POSTGRES_IMAGE="${POSTGRES_IMAGE:-postgres:17.7}"
OPENCLAW_VERSION="${OPENCLAW_VERSION:-2026.6.6}"
PLAYWRIGHT_VERSION="${PLAYWRIGHT_VERSION:-1.60.0}"
GOOGLE_CHROME_VERSION="${GOOGLE_CHROME_VERSION:-149.0.7827.114-1}"

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
  local wheel_dir="${WORKDIR}/packages/pip"

  mkdir -p "${apt_dir}" "${apt_lists}" "${wheel_dir}"

  docker run --rm --platform "${platform}" \
    -e DISTRO_ID="${DISTRO_ID}" \
    -e DISTRO_VERSION="${DISTRO_VERSION}" \
    -e NODEJS_MAJOR_VERSIONS="${NODEJS_MAJOR_VERSIONS}" \
    -e NODEJS_22_VERSION="${NODEJS_22_VERSION}" \
    -e NODEJS_24_VERSION="${NODEJS_24_VERSION}" \
    -e GOOGLE_CHROME_VERSION="${GOOGLE_CHROME_VERSION}" \
    -e LITELLM_DEBIAN_11_VERSION="${LITELLM_DEBIAN_11_VERSION}" \
    -v "${apt_dir}:/offline-apt" \
    -v "${apt_lists}:/offline-meta" \
    -v "${wheel_dir}:/offline-pip" \
    -v "${WORKDIR}/repos/litellm:/litellm-src:ro" \
    "${image}" \
    bash -lc "$(cat <<'CONTAINER'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y ca-certificates curl gnupg dpkg-dev apt-transport-https

install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key -o /etc/apt/keyrings/nodesource.asc
for major in ${NODEJS_MAJOR_VERSIONS}; do
  echo "deb [signed-by=/etc/apt/keyrings/nodesource.asc] https://deb.nodesource.com/node_${major}.x nodistro main" \
    > "/etc/apt/sources.list.d/nodesource-node${major}.list"
done
curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/gpg.key -o /etc/apt/keyrings/caddy-stable.asc
echo "deb [signed-by=/etc/apt/keyrings/caddy-stable.asc] https://dl.cloudsmith.io/public/caddy/stable/deb/debian any-version main" \
  > /etc/apt/sources.list.d/caddy-stable.list
if [ "$(dpkg --print-architecture)" = "amd64" ]; then
  curl -fsSL https://dl.google.com/linux/linux_signing_key.pub \
    | gpg --dearmor -o /etc/apt/keyrings/google-linux-signing-key.gpg
  echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/google-linux-signing-key.gpg] https://dl.google.com/linux/chrome/deb/ stable main" \
    > /etc/apt/sources.list.d/google-chrome.list
fi
curl -fsSL https://dl.yarnpkg.com/debian/pubkey.gpg -o /etc/apt/keyrings/yarn.asc
echo "deb [signed-by=/etc/apt/keyrings/yarn.asc] https://dl.yarnpkg.com/debian/ stable main" \
  > /etc/apt/sources.list.d/yarn.list
if curl -fsSL https://download.docker.com/linux/${DISTRO_ID}/gpg -o /etc/apt/keyrings/docker.asc; then
  . /etc/os-release
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${DISTRO_ID} ${VERSION_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
fi

apt-get update -y

required_packages=(
  ansible git curl ca-certificates gnupg jq rsync unzip wget xdg-utils
  caddy xfce4 python3 python3-pip python3-venv python3-dev python3-setuptools
  build-essential pkg-config libpq-dev python-is-python3 pandoc nodejs yarn golang-go
  texlive-xetex texlive-latex-extra texlive-fonts-recommended
  texlive-lang-chinese latexmk fonts-noto-cjk
  fonts-noto-cjk-extra fonts-wqy-zenhei fonts-wqy-microhei
)

resolve_required_package() {
  local candidate
  for candidate in "$@"; do
    if apt-cache show "${candidate}" >/dev/null 2>&1; then
      printf '%s\n' "${candidate}"
      return
    fi
  done
  echo "Required APT package is unavailable for this target: $*" >&2
  exit 1
}

case "$(dpkg --print-architecture)" in
  amd64)
    if ! apt-cache show "google-chrome-stable=${GOOGLE_CHROME_VERSION}" >/dev/null 2>&1; then
      echo "Required Google Chrome version is unavailable: ${GOOGLE_CHROME_VERSION}" >&2
      exit 1
    fi
    ;;
  arm64)
    browser_dependency_groups=(
      "libasound2 libasound2t64"
      "libatk-bridge2.0-0 libatk-bridge2.0-0t64"
      "libatk1.0-0 libatk1.0-0t64"
      "libatspi2.0-0 libatspi2.0-0t64"
      "libcairo2"
      "libcups2 libcups2t64"
      "libdbus-1-3"
      "libdrm2"
      "libgbm1"
      "libglib2.0-0 libglib2.0-0t64"
      "libnspr4"
      "libnss3"
      "libpango-1.0-0"
      "libx11-6"
      "libxcb1"
      "libxcomposite1"
      "libxdamage1"
      "libxext6"
      "libxfixes3"
      "libxkbcommon0"
      "libxrandr2"
    )
    : > /offline-meta/browser-deb-packages.txt
    for dependency_group in "${browser_dependency_groups[@]}"; do
      read -r -a dependency_candidates <<<"${dependency_group}"
      resolved_dependency="$(resolve_required_package "${dependency_candidates[@]}")"
      required_packages+=("${resolved_dependency}")
      printf '%s\n' "${resolved_dependency}" >> /offline-meta/browser-deb-packages.txt
    done
    ;;
esac
packages=()

for package in "${required_packages[@]}"; do
  if ! apt-cache show "${package}" >/dev/null 2>&1; then
    echo "Required APT package is unavailable for this target: ${package}" >&2
    exit 1
  fi
  packages+=("${package}")
done

if [ "$(dpkg --print-architecture)" = "amd64" ]; then
  packages+=("google-chrome-stable=${GOOGLE_CHROME_VERSION}")
fi

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

apt-get install --download-only -y --no-install-recommends "${packages[@]}"
apt-get download "nodejs=${NODEJS_22_VERSION}-1nodesource1"
apt-get download "nodejs=${NODEJS_24_VERSION}-1nodesource1"
cp -n ./*.deb /offline-apt/ 2>/dev/null || true
find /var/cache/apt/archives -name '*.deb' -exec cp -n {} /offline-apt/ \;
cd /offline-apt
dpkg-scanpackages --multiversion . /dev/null | gzip -9c > Packages.gz
find . -maxdepth 1 -name '*.deb' -printf '%f\n' | sort > /offline-meta/deb-files.txt

apt-get install -y --no-install-recommends \
  build-essential git libpq-dev python3 python3-dev python3-pip python3-venv
python3 -m venv /tmp/ai-workspace-wheel-builder
/tmp/ai-workspace-wheel-builder/bin/pip install --upgrade pip setuptools wheel
litellm_package_spec="/litellm-src[proxy]"
if [ "${DISTRO_ID}:${DISTRO_VERSION}" = "debian:11" ]; then
  litellm_package_spec="litellm[proxy]==${LITELLM_DEBIAN_11_VERSION}"
fi
/tmp/ai-workspace-wheel-builder/bin/pip wheel \
  --wheel-dir /offline-pip \
  "${litellm_package_spec}" \
  prisma \
  psycopg2-binary
CONTAINER
)"
}

warm_npm_dependency_cache() {
  local npm_cache_dir="${WORKDIR}/packages/npm-cache"
  mkdir -p "${npm_cache_dir}"
  docker run --rm --platform "linux/${ARCH}" \
    -e OPENCLAW_VERSION="${OPENCLAW_VERSION}" \
    -e PLAYWRIGHT_VERSION="${PLAYWRIGHT_VERSION}" \
    -v "${npm_cache_dir}:/offline-cache" \
    -v "${WORKDIR}/repos/xworkspace-console/dashboard:/sources/dashboard:ro" \
    -v "${WORKDIR}/repos/qmd:/sources/qmd:ro" \
    node:24-bookworm \
    bash -lc "$(cat <<'CONTAINER'
set -euo pipefail
export npm_config_cache=/offline-cache
export npm_config_audit=false
export npm_config_fund=false

mkdir -p /tmp/projects
cp -a /sources/dashboard /tmp/projects/dashboard
cp -a /sources/qmd /tmp/projects/qmd

(
  cd /tmp/projects/dashboard
  npm ci --ignore-scripts --no-audit --no-fund
)
(
  cd /tmp/projects/qmd
  npm install --ignore-scripts --no-audit --no-fund --package-lock=false
)

npm install --ignore-scripts --no-audit --no-fund --prefix /tmp/global \
  opencode-ai \
  @google/gemini-cli \
  @openai/codex \
  @anthropic-ai/claude-code \
  "openclaw@${OPENCLAW_VERSION}" \
  "@openclaw/codex@${OPENCLAW_VERSION}" \
  "playwright@${PLAYWRIGHT_VERSION}"
CONTAINER
)"
}

download_playwright_browser() {
  if [ "${ARCH}" != "arm64" ]; then
    return
  fi

  local browser_dir="${WORKDIR}/packages/playwright-browsers"
  mkdir -p "${browser_dir}"
  docker run --rm --platform "linux/${ARCH}" \
    -e PLAYWRIGHT_VERSION="${PLAYWRIGHT_VERSION}" \
    -e PLAYWRIGHT_BROWSERS_PATH=/offline-browsers \
    -v "${browser_dir}:/offline-browsers" \
    node:24-bookworm \
    bash -lc 'npx --yes "playwright@${PLAYWRIGHT_VERSION}" install chromium'

  if ! find "${browser_dir}" -type f \
      \( -path '*/chrome-linux/chrome' -o -path '*/chrome-linux64/chrome' \) \
      -print -quit | grep -q .; then
    echo "Bundled Playwright Chromium executable was not found for ${ARCH}" >&2
    exit 1
  fi
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

build_xworkmate_bridge_binary() {
  local bin_dir="${WORKDIR}/packages/bin"
  mkdir -p "${bin_dir}"
  docker run --rm --platform "linux/${ARCH}" \
    -e GOOS=linux \
    -e GOARCH="${ARCH}" \
    -e CGO_ENABLED=0 \
    -v "${WORKDIR}/repos/xworkmate-bridge:/src:ro" \
    -v "${bin_dir}:/out" \
    golang:1.25-bookworm \
    bash -lc 'cd /src && /usr/local/go/bin/go build -buildvcs=false -trimpath -o "/out/xworkmate-go-core.${GOARCH}" .'
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
    "googleChrome": "${GOOGLE_CHROME_VERSION}",
    "litellmDebian11": "${LITELLM_DEBIAN_11_VERSION}",
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
  warm_npm_dependency_cache
  download_playwright_browser
  download_binaries
  build_xworkmate_bridge_binary
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
