#!/usr/bin/env bash
set -euo pipefail

USER_HOME="${HOME}"

rm -rf "${USER_HOME}/.config/xfce4/panel"
rm -rf "${USER_HOME}/.config/xfce4/xfconf/xfce-perchannel-xml"
rm -f "${USER_HOME}/.config/autostart/xworkspace-*.desktop"
rm -f "${USER_HOME}/.config/systemd/user/xworkspace-*.service"
rm -f "${USER_HOME}/.config/systemd/user/default.target.wants/xworkspace-*.service"

echo "XFCE/XWorkspace profile reset complete."
