#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${ROOT_DIR}/config/xworkspace-desktop.yaml"

read_yaml() {
  python3 - "$CONFIG_FILE" "$1" <<'PY'
import sys
from pathlib import Path
import yaml

config_path = Path(sys.argv[1])
path = sys.argv[2].split(".")
data = yaml.safe_load(config_path.read_text())
value = data
for part in path:
    value = value[part]
print(value)
PY
}

DASHBOARD_URL="$(read_yaml desktop.dashboard_url)"
BROWSER_BINARY="$(read_yaml desktop.browser_binary)"
BROWSER_FALLBACK="$(read_yaml desktop.browser_fallback)"
URL="${1:-${DASHBOARD_URL}}"

echo "Starting XWorkspace Chrome Shell (minimal mode)..."
echo "URL: ${URL}"

if command -v "${BROWSER_BINARY}" >/dev/null 2>&1; then
  exec "${BROWSER_BINARY}" \
    --app="${URL}" \
    --user-data-dir="${HOME}/.config/xworkspace-chrome-minimal" \
    --profile-directory=Default \
    --no-first-run \
    --disable-session-crashed-bubble \
    --disable-sync \
    --disable-infobars \
    --disable-features=TranslateUI \
    --new-window \
    --kiosk \
    --start-maximized \
    --autoplay-policy=no-user-gesture-required
fi

exec "${BROWSER_FALLBACK}" \
  --app="${URL}" \
  --user-data-dir="${HOME}/.config/xworkspace-chromium-minimal" \
  --no-first-run \
  --disable-session-crashed-bubble \
  --disable-sync \
  --disable-infobars \
  --new-window \
  --kiosk \
  --start-maximized \
  --autoplay-policy=no-user-gesture-required