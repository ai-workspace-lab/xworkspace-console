# XWorkspace Console

`xworkspace-console` is now a desktop-and-console project centered on:

- YAML configuration
- Go status collection API
- React + Vite + TypeScript dashboard
- systemd user services
- XFCE / GTK / XDG desktop templates

Flutter, Dart, and the earlier static web shell have been removed from this repo.

## Core Structure

- `config/xworkspace-desktop.yaml`
  - single source of truth for desktop ports, browser choice, and service naming
- `scripts/`
  - setup, reset, and browser launch helpers
- `config/xfce4/`
  - XFCE panel, window manager, session, and shortcut templates
- `config/autostart/`
  - XDG autostart entry for the console
- `config/systemd/user/`
  - systemd user services for console, OpenClaw, bridge, LiteLLM, and Vault
- `api/`
  - Go API exposing `/health`, `/services`, and `/metrics/simple`
- `dashboard/`
  - React + Vite + TypeScript dashboard MVP

## Primary Service Name

The repo standardizes on `xworkspace-console` as the main local control-plane UI service.

Older overlapping names such as `xworkspace-dashboard` and `xworkspace-portal` are treated as historical concepts, not separate primary services in this repo.

## Online Alignment

The live target host `ubuntu@xworkmate-bridge.svc.plus` currently aligns to `jp-xhttp-contabo.svc.plus`.

The real online service shapes used as reference here are:

- `xworkmate-bridge.service`
  - `ExecStart=/home/ubuntu/.local/bin/xworkmate-go-core serve --listen 127.0.0.1:8787`
  - `WorkingDirectory=/opt/cloud-neutral/xworkmate-bridge`
- `openclaw-gateway.service`
  - `ExecStart=/home/ubuntu/.local/bin/openclaw gateway run --port 18789 --force`
  - `WorkingDirectory=/home/ubuntu`

The local repo mirrors those startup patterns with:

- `xworkspace-bridge.service`
- `xworkspace-openclaw.service`

## Endpoint Plan

The canonical local Console endpoint is:

- `http://127.0.0.1:17000`

Port ownership:

- `17000`: XWorkspace Console React dashboard
- `8788`: XWorkspace Go status API
- `8787`: XWorkmate Bridge control plane
- `18789`: OpenClaw Gateway
- `4000`: LiteLLM UI/API
- `8200`: Vault
- `7681`: ttyd embedded terminal
- `7000`: deprecated legacy portal, do not use for new Console deployments

See `docs/operations/service-port-plan.md` for the live-host inspection and migration order.

## Quick Start

```bash
./scripts/setup-xworkspace-desktop.sh
```

## Reset

```bash
./scripts/reset-xfce-profile.sh
```

## Notes

- XFCE remains the desktop base layer.
- Dashboard is React + Vite + TypeScript.
- Status API is Go.
- Service management is systemd user units.
- Theme and shell customization are handled through XFCE config, GTK/XDG-compatible templates, and shell scripts.
