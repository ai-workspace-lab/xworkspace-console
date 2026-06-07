#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
USER_HOME="${HOME}"
CONFIG_FILE="${ROOT_DIR}/config/xworkspace-desktop.yaml"

read_yaml() {
  python3 - "$CONFIG_FILE" "$1" <<'PY'
import sys
from pathlib import Path

config_path = Path(sys.argv[1])
path = sys.argv[2].split(".")

try:
    import yaml
except Exception as exc:
    raise SystemExit(f"pyyaml is required: {exc}")

data = yaml.safe_load(config_path.read_text())
value = data
for part in path:
    value = value[part]
print(value)
PY
}

sudo apt-get update
sudo apt-get install -y \
  xfce4 xfce4-panel xfwm4 thunar \
  chromium-browser \
  plank \
  curl jq \
  golang-go \
  nodejs npm \
  python3-yaml

DASHBOARD_PORT="$(read_yaml desktop.dashboard_port)"
CONSOLE_SERVICE="$(read_yaml services.console.name)"
OPENCLAW_SERVICE="$(read_yaml services.openclaw.name)"
BRIDGE_SERVICE="$(read_yaml services.bridge.name)"
LITELLM_SERVICE="$(read_yaml services.litellm.name)"
VAULT_SERVICE="$(read_yaml services.vault.name)"

mkdir -p "${USER_HOME}/.config/autostart"
mkdir -p "${USER_HOME}/.config/xfce4/panel"
mkdir -p "${USER_HOME}/.config/xfce4/xfconf/xfce-perchannel-xml"
mkdir -p "${USER_HOME}/.config/systemd/user/default.target.wants"

cp -R "${ROOT_DIR}/config/xfce4/." "${USER_HOME}/.config/xfce4/"
cp -R "${ROOT_DIR}/config/autostart/." "${USER_HOME}/.config/autostart/"
cp -R "${ROOT_DIR}/config/systemd/." "${USER_HOME}/.config/systemd/user/"

python3 - "${USER_HOME}/.config/autostart/xworkspace-console.desktop" "${DASHBOARD_PORT}" <<'PY'
import sys
from pathlib import Path

desktop_file = Path(sys.argv[1])
port = sys.argv[2]
text = desktop_file.read_text()
desktop_file.write_text(
    text.replace("http://localhost:8787", f"http://127.0.0.1:{port}")
    .replace("http://127.0.0.1:7000", f"http://127.0.0.1:{port}")
    .replace("http://127.0.0.1:17000", f"http://127.0.0.1:{port}")
)
PY

if command -v systemctl >/dev/null 2>&1; then
  systemctl --user daemon-reload || true
  systemctl --user enable --now "${CONSOLE_SERVICE}" || true
  systemctl --user enable --now "${OPENCLAW_SERVICE}" || true
  systemctl --user enable --now "${BRIDGE_SERVICE}" || true
  systemctl --user enable --now "${LITELLM_SERVICE}" || true
  systemctl --user enable --now "${VAULT_SERVICE}" || true
fi

echo "Installed XWorkspace Desktop templates."
