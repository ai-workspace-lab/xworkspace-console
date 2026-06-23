[🇺🇸 English](../../README.md) | [🇨🇳 中文](../../README.zh.md)

# Repository Overview

This document collects the repository details that are useful for maintainers and integrators, while keeping the homepage README focused on entry points.

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

See [`docs/operations/service-port-plan.md`](./operations/service-port-plan.md) for the live-host inspection and migration order.

## Notes

- XFCE remains the desktop base layer.
- Dashboard is React + Vite + TypeScript.
- Status API is Go.
- Service management is systemd user units.
- Theme and shell customization are handled through XFCE config, GTK/XDG-compatible templates, and shell scripts.
