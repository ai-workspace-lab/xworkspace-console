#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${ROOT_DIR}/config/xworkspace-desktop.yaml"

MODE="${1:-xfce}"

case "${MODE}" in
  xfce)
    XFCE_DIR="${HOME}/.config/xfce4"
    DEST_DIR="${XFCE_DIR}"
    ;;
  minimal|xface-minimal)
    XFCE_DIR="${ROOT_DIR}/config/xface-minimal"
    DEST_DIR="${HOME}/.config/xfce4"
    ;;
  *)
    echo "Unknown mode: ${MODE}" >&2
    echo "Usage: $0 [xfce|minimal]" >&2
    exit 1
    ;;
esac

mkdir -p "${DEST_DIR}"
mkdir -p "${HOME}/.config/xfce4/panel"
mkdir -p "${HOME}/.config/xfce4/xfconf/xfce-perchannel-xml"
mkdir -p "${HOME}/.config/autostart"
mkdir -p "${HOME}/.config/systemd/user"

echo "Setting up XWorkspace Desktop in ${MODE} mode..."

cp -R "${ROOT_DIR}/config/systemd/." "${HOME}/.config/systemd/user/"

if [[ -d "${XFCE_DIR}" ]]; then
  cp -R "${XFCE_DIR}/." "${DEST_DIR}/"
fi

cp -R "${ROOT_DIR}/config/autostart/." "${HOME}/.config/autostart/"

python3 - "${HOME}/.config/autostart/xworkspace-console.desktop" <<'PY'
import sys
from pathlib import Path

desktop_file = Path(sys.argv[1])
text = desktop_file.read_text()
desktop_file.write_text(text.replace("http://127.0.0.1:17000", "http://127.0.0.1:17000"))
PY

if command -v systemctl >/dev/null 2>&1; then
  systemctl --user daemon-reload || true
fi

echo "XWorkspace Desktop ${MODE} mode configured."
echo "To apply: logout and login, or run 'xfce4-session --replace' for immediate effect."