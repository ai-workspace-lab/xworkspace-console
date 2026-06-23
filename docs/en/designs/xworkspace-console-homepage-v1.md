[🇺🇸 English](../../../README.md) | [🇨🇳 中文](../../../README.zh.md)

# XWorkspace Console Homepage V1

Date: 2026-06-07
Status: First implementation design

## Goal

Build the first React implementation of the `xworkspace-console` homepage based on the provided control-plane design reference.

The first version may use temporary mock data, but the component structure must be ready for real runtime integration:

- custom tabs
- service status
- active agents
- recent tasks
- artifacts
- system health
- embedded `ttyd`
- quick access links
- system telemetry integration points

## Information Architecture

The homepage is organized around an operations dashboard:

- Left navigation
  - Workspace
  - Dashboard
  - Agents
  - Tasks
  - Artifacts
  - OpenClaw
  - Bridge
  - LiteLLM
  - Vault
  - Runtime
  - Terminal
  - Settings
- Top status bar
  - CPU
  - GPU
  - VPN state
  - notifications
  - user/profile
- Main overview
  - metric cards
  - services status
  - active agents
  - recent tasks
  - artifacts
  - system health
  - quick access

## Required Links

The following navigation and quick access targets are canonical for V1:

- OpenClaw: `http://127.0.0.1:18789/channels`
- Vault: `http://127.0.0.1:8200`
- LiteLLM: `http://127.0.0.1:4000/ui`
- Terminal: `http://127.0.0.1:7681`

## Custom Tabs

Tabs should be represented as data, not hardcoded across the UI.

Initial tab shape:

```ts
type Tab = {
  id: string;
  label: string;
  href: string;
  kind: 'internal' | 'external' | 'embed';
};
```

This allows the homepage to support later user-defined tabs from YAML or an API response.

## Embedded Terminal

The Terminal tab should render a real `ttyd` embed:

```text
http://127.0.0.1:7681
```

The first implementation can use an iframe. A later version may proxy or authenticate the terminal if needed.

## System Probes

The homepage should be designed to consume local status data from the Go API and related observability tools.

Initial local API:

- `GET http://127.0.0.1:8788/health`
- `GET http://127.0.0.1:8788/services`
- `GET http://127.0.0.1:8788/metrics/simple`

Future integrations:

- Prometheus metrics
- Vector logs
- local service logs
- agent readiness probes
- Vault connectivity
- OpenClaw gateway state

## Mock Data Policy

V1 may use mock data for:

- metric cards
- agents
- tasks
- artifacts
- system health score

V1 should attempt to read `/services` from the Go API when available and gracefully fall back to mock service rows.

## Visual Direction

The provided design reference uses a bright, clean operations console style:

- white panels
- blue primary action color
- subtle borders
- compact tables
- low-noise status indicators
- rounded corners kept moderate
- dashboard-first layout, not a marketing page

Cards should be used for repeated dashboard items and bounded panels only.

## V1 Implementation Notes

Implemented in:

- `dashboard/src/main.tsx`
- `dashboard/src/styles.css`

V1 includes:

- mock metrics
- mock agents
- mock tasks
- mock artifacts
- real external links for OpenClaw, Vault, LiteLLM
- embedded `ttyd` terminal tab
- attempted service status fetch from `http://127.0.0.1:8788/services`

## Next Steps

- Move tab definitions to `config/xworkspace-desktop.yaml`
- Add a `/tabs` endpoint to the Go API
- Add CORS support if dashboard and API are served from separate ports
- Add real host metrics for CPU, memory, disk, and network
- Add Prometheus and Vector probes
- Replace letter placeholders with a formal icon system
