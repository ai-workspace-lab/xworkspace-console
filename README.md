# XWorkspace Console

XWorkspace Console is the local AI workspace control plane for AI Workspace Lab. It brings together a React dashboard, Go status API, systemd user services, and XFCE desktop templates into one tabbed surface for services, runtime, terminal access, and workspace navigation.

## About

- Single entry point for the workspace UI at `http://127.0.0.1:17000`
- Tab-first console for Workspace, services, runtime, and embedded tools
- Designed to coordinate local AI services, gateway access, and desktop bootstrap flows
- Backed by `dashboard/`, `api/`, `config/`, `scripts/`, and `docs/`

## Start TLDR

1. Start the all-in-one installer:

```bash
curl -sfL https://raw.githubusercontent.com/ai-workspace-lab/xworkspace-console/main/scripts/setup-ai-workspace-all-in-one.sh | bash -
```

2. Or launch the local desktop console:

```bash
./scripts/setup-xworkspace-desktop.sh
```

3. Open the console:

```text
http://127.0.0.1:17000
```

## Tab Pages

The console is organized around tabs so the workspace can switch between overview, services, and custom artifact views.

### Workspace and Service Tabs

- `Workspace` for the main overview
- `OpenClaw` for gateway access
- `LiteLLM` for model routing and provider administration
- `Vault` for secrets and auth
- `Terminal` for the embedded local shell

### Image / Video

Image and video workflows fit naturally as custom tabs inside the same console shell. This keeps artifact review, service switching, and runtime operations in one place instead of scattering them across separate apps.

![XWorkspace Console dashboard preview](./dashboard-preview.png)

![XWorkspace Console status dropdown](./dashboard-status-dropdown.png)

## Download

- Latest source: [GitHub repository](https://github.com/ai-workspace-lab/xworkspace-console)
- Releases: [GitHub Releases](https://github.com/ai-workspace-lab/xworkspace-console/releases)
- Bootstrap script: `scripts/setup-ai-workspace-all-in-one.sh`
- Offline installer docs: [`docs/OFFLINE_AI_WORKSPACE_INSTALLER.md`](docs/OFFLINE_AI_WORKSPACE_INSTALLER.md)

## Docs / Links

- [`docs/SETUP_AI_WORKSPACE_ALL_IN_ONE.md`](docs/SETUP_AI_WORKSPACE_ALL_IN_ONE.md)
- [`docs/OFFLINE_AI_WORKSPACE_INSTALLER.md`](docs/OFFLINE_AI_WORKSPACE_INSTALLER.md)
- [`docs/operations/service-port-plan.md`](docs/operations/service-port-plan.md)
- [`docs/designs/2026-06-07-ai-workspace-desktop-design.md`](docs/designs/2026-06-07-ai-workspace-desktop-design.md)

## Core Structure

- `config/xworkspace-desktop.yaml`
  - single source of truth for desktop ports, browser choice, and service naming
- `scripts/`
  - setup, reset, install, and browser launch helpers
- `config/xfce4/`
  - XFCE panel, window manager, session, and shortcut templates
- `config/autostart/`
  - XDG autostart entry for the console
- `config/systemd/user/`
  - systemd user services for console, OpenClaw, bridge, LiteLLM, and Vault
- `api/`
  - Go API exposing `/health`, `/services`, and `/metrics/simple`
- `dashboard/`
  - React + Vite + TypeScript dashboard

## Primary Service Name

The repo standardizes on `xworkspace-console` as the main local control-plane UI service.

Older overlapping names such as `xworkspace-dashboard` and `xworkspace-portal` are treated as historical concepts, not separate primary services in this repo.

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

See [`docs/operations/service-port-plan.md`](docs/operations/service-port-plan.md) for the live-host inspection and migration order.

## Notes

- XFCE remains the desktop base layer.
- Dashboard is React + Vite + TypeScript.
- Status API is Go.
- Service management is systemd user units.
- Theme and shell customization are handled through XFCE config, GTK/XDG-compatible templates, and shell scripts.
