[🇺🇸 English](../../../README.md) | [🇨🇳 中文](../../../README.zh.md)

# AI Workspace Desktop Design

Date: 2026-06-07
Project: `xworkspace-console`
Status: Draft for implementation alignment

## 1. Overview

This document defines the target design for the AI Workspace desktop environment built on top of XFCE, with `xworkspace-console` as the merged implementation repository.

The goal is not to build a new desktop environment. The goal is to assemble a minimal, reliable AI workspace shell by combining:

- XFCE as the desktop base layer
- XFCE panel and GTK/XDG-compatible configuration for desktop chrome
- `Plank` as the preferred auto-hide dock
- `systemd --user` for per-user service orchestration
- `Go` for the local status collection API
- `React + Vite + TypeScript` for the dashboard UI
- `ttyd` for the embedded terminal surface
- `Chrome` or `Chromium` app mode for the primary operator entrypoint

The intended visual direction is a low-distraction workspace that feels closer to NomadBSD, ChromeOS, and a simplified macOS Dock setup than to a traditional Linux desktop.

## 2. Product Goals

The desktop should boot into a focused AI operations environment where the browser-based control plane is the primary user experience.

Primary outcomes:

- A user signs into XFCE and lands in a minimal workspace, not a classic Linux desktop
- The top status bar surfaces only essential runtime state
- The bottom dock provides fast access to a fixed set of operator tools
- The browser opens directly into the XWorkspace control plane
- OpenClaw, Bridge, LiteLLM, Vault, and console services are managed and inspectable through systemd
- The control plane can show local service health, basic host metrics, and terminal access

## 3. Non-Goals

The first phase explicitly avoids these directions:

- No custom window manager
- No custom desktop shell framework
- No full desktop theming engine
- No KDE or GNOME dependencies
- No traditional application launcher menu as a primary interaction model
- No desktop widgets or icon clutter
- No attempt to replace XFCE internals with a new compositor or shell

## 4. User Experience

### 4.1 Desktop Experience

The default desktop session should feel intentional and appliance-like:

- Top panel height between 28px and 32px
- Left side of top panel shows `XWorkspace`
- Right side shows compact indicators for CPU, memory, network, agent readiness, vault status, and time
- No desktop icons
- No visible applications menu
- Bottom dock is hidden by default and revealed on pointer-to-screen-edge
- Dock entries are fixed and role-based, not open-ended

### 4.2 Dock Entries

The preferred first set of dock actions is:

- Browser
- Terminal
- Files
- VS Code
- XWorkmate
- OpenClaw

These launchers should point to stable system binaries or app-mode URLs, not ephemeral user shell aliases.

### 4.3 Browser Entry

The primary operator shell is Chrome or Chromium app mode:

- Preferred default URL: `http://127.0.0.1:17000`
- Alternate deployment URL: `https://workspace.local`

The app-mode launch path should be encapsulated in a script rather than duplicated across autostart and service files.

## 5. Architecture

The design is split into five layers:

1. Desktop shell layer
2. Service orchestration layer
3. Local status API layer
4. Dashboard UI layer
5. Deployment/configuration layer

### 5.1 Desktop Shell Layer

This layer is composed of:

- XFCE session
- XFCE top panel
- GTK/XDG configuration files
- Plank dock
- XDG autostart entries

Responsibilities:

- enforce minimal desktop layout
- disable desktop icons and traditional menu clutter
- expose a stable operator shell
- preserve compatibility with standard Linux tooling

### 5.2 Service Orchestration Layer

This layer uses `systemd --user`.

Managed services:

- `xworkspace-console.service`
- `xworkspace-openclaw.service`
- `xworkspace-bridge.service`
- `xworkspace-litellm.service`
- `xworkspace-vault.service`

Responsibilities:

- service startup order
- restart policy
- operator-facing unit naming
- local introspection via `systemctl --user`

### 5.3 Local Status API Layer

This layer is written in `Go`.

Responsibilities:

- expose health endpoints for the dashboard
- normalize service state from systemd
- collect simple machine metrics
- answer lightweight polling traffic from the local dashboard

Endpoints:

- `/health`
- `/services`
- `/metrics/simple`

The API should stay intentionally small and local-first.

### 5.4 Dashboard UI Layer

This layer is written in `React + Vite + TypeScript`.

Responsibilities:

- render service cards
- render task and agent placeholders in MVP
- surface artifacts and settings sections
- embed or link terminal access through `ttyd`
- act as the default browser control plane

The visual language should be dark, precise, and operational rather than decorative.

### 5.5 Deployment and Configuration Layer

This layer uses:

- shell scripts
- YAML configuration
- XFCE XML templates
- systemd service files

The repo should maintain a single human-editable YAML config file for desktop-level defaults such as ports, browser preference, and service naming. Generated or copied runtime files can still be XML or `.desktop` files where required by XFCE and XDG.

## 6. Canonical Repository Structure

The merged repository should keep this shape:

```text
xworkspace-console/
├─ api/
├─ assets/
│  ├─ icons/
│  ├─ themes/
│  └─ wallpaper/
├─ config/
│  ├─ autostart/
│  ├─ systemd/
│  │  └─ user/
│  ├─ xfce4/
│  └─ xworkspace-desktop.yaml
├─ dashboard/
│  ├─ src/
│  ├─ package.json
│  ├─ tsconfig.json
│  └─ vite.config.ts
├─ docs/
│  └─ designs/
├─ scripts/
│  ├─ reset-xfce-profile.sh
│  ├─ setup-xworkspace-desktop.sh
│  └─ start-chromium-console.sh
└─ README.md
```

Removed from scope:

- Flutter
- Dart
- static web shell duplication

## 7. Naming Model

The repository standardizes on `xworkspace-console` as the primary control-plane name.

Naming decision:

- Keep: `xworkspace-console`
- Keep: `xworkspace-openclaw`
- Keep: `xworkspace-bridge`
- Keep: `xworkspace-litellm`
- Keep: `xworkspace-vault`
- Treat as historical/overlapping labels only: `xworkspace-dashboard`, `xworkspace-portal`

Reasoning:

- `console` is broad enough to cover desktop shell plus browser control plane
- `dashboard` is too narrow once service orchestration and desktop concerns are merged
- `portal` overlaps with one specific web surface and causes naming duplication

## 8. Online Environment Alignment

The live reference host is:

- SSH entry: `ubuntu@xworkmate-bridge.svc.plus`
- effective host: `jp-xhttp-contabo.svc.plus`

Reference online service behavior already observed:

### 8.1 Bridge

Live unit:

- `xworkmate-bridge.service`

Observed shape:

- `WorkingDirectory=/opt/cloud-neutral/xworkmate-bridge`
- `ExecStart=/home/ubuntu/.local/bin/xworkmate-go-core serve --listen 127.0.0.1:8787`

### 8.2 OpenClaw

Live unit:

- `openclaw-gateway.service`

Observed shape:

- `WorkingDirectory=/home/ubuntu`
- `ExecStart=/home/ubuntu/.local/bin/openclaw gateway run --port 18789 --force`

### 8.3 Implication

The local repo should preserve these real startup patterns in the service templates, even if repo-level names are normalized to:

- `xworkspace-bridge.service`
- `xworkspace-openclaw.service`

This prevents the desktop repo from drifting away from the live environment.

## 9. Systemd Design

### 9.1 Units

Required user units:

- `xworkspace-console.service`
- `xworkspace-openclaw.service`
- `xworkspace-bridge.service`
- `xworkspace-litellm.service`
- `xworkspace-vault.service`

Recommended optional units later:

- `xworkspace-status-api.service`
- `xworkspace-ttyd.service`

### 9.2 Service Rules

Each service should define:

- a clear `Description`
- `After=network-online.target` when it depends on network readiness
- `Restart=always`
- explicit `WorkingDirectory` when runtime behavior depends on cwd
- explicit `Environment=` entries when tool paths or configs matter

### 9.3 Console Service

`xworkspace-console.service` should run the React dashboard dev server in MVP, but the intended evolution is:

- dev mode during early iteration
- built static assets served by a lightweight local web server later

That future transition should not change the service name.

## 10. YAML Configuration Model

Primary config file:

- `config/xworkspace-desktop.yaml`

Responsibilities:

- browser binary selection
- dashboard URL and ports
- service naming defaults
- shell-level UI defaults such as dock strategy and panel height

The setup scripts should read this YAML and use it to patch or generate deployment-facing files when reasonable.

## 11. XFCE and Theme Configuration

### 11.1 XFCE

Config templates should remain in `config/xfce4/`.

Key responsibilities:

- panel placement
- panel size
- shortcut defaults
- session behavior
- window focus defaults

### 11.2 GTK / XDG

Theme customization should be kept lightweight:

- GTK theme selection
- icon theme selection
- XDG autostart entries
- desktop icon suppression

No large theming subsystem is needed in MVP.

## 12. Dashboard MVP

### 12.1 Sections

The dashboard should expose these sections:

- Services
- Tasks
- Agents
- Artifacts
- Terminal
- Settings

### 12.2 Terminal

Terminal behavior should be one of:

- embedded `ttyd` frame
- local link-out to `ttyd`

MVP can begin with an embedded panel or status-linked shell area.

### 12.3 Visual Direction

The interface should follow:

- dark background
- blue/white operational accents
- low visual noise
- strong spacing and readable density
- appliance-like focus rather than marketing aesthetics

## 13. Go API MVP

### 13.1 Endpoints

- `/health`
  - status, arch, OS, CPU count, service snapshot
- `/services`
  - normalized systemd service states
- `/metrics/simple`
  - machine-readable metrics line output

### 13.2 Data Sources

MVP may use:

- `systemctl --user is-active`
- standard library HTTP only
- simple host runtime introspection

Later versions may add:

- CPU percentage
- memory usage
- disk usage
- network availability
- agent readiness probes

## 14. Setup and Reset Flows

### 14.1 Setup

`scripts/setup-xworkspace-desktop.sh` should:

- install required packages
- create target config directories
- copy XFCE and systemd templates
- copy XDG autostart entry
- enable relevant user services

### 14.2 Reset

`scripts/reset-xfce-profile.sh` should:

- remove copied XFCE panel/session config
- remove XWorkspace autostart entry
- remove XWorkspace user service files and symlinks

The reset path must avoid damaging unrelated shell configuration.

## 15. Risks and Constraints

### 15.1 Browser Binary Variants

Different Debian/Ubuntu variants may provide:

- `google-chrome`
- `chromium-browser`
- `chromium`

The launcher must support at least a preferred binary plus fallback.

### 15.2 XFCE Plugin Availability

Dock strategy may vary by distro packaging:

- prefer `Plank`
- use `xfce4-docklike-plugin` as fallback when needed

### 15.3 Dev Server vs Static Build

Running Vite in dev mode is acceptable in MVP, but long-term desktop reliability improves if the dashboard is built and served as static files.

### 15.4 Online Drift

The desktop repo must periodically re-validate service templates against the live host to avoid stale assumptions, especially for:

- OpenClaw startup flags
- bridge binary path
- auth-related environment variables

## 16. Implementation Roadmap

### Phase 1

- remove Flutter/Dart leftovers
- keep YAML + Go + React + XFCE/systemd only
- align openclaw and bridge service templates with live host
- keep dashboard as local Vite MVP

### Phase 2

- add real host metrics to the Go API
- add `ttyd` integration to dashboard
- add generated dock/panel setup behavior from YAML config
- improve Plank auto-hide setup and launcher provisioning

### Phase 3

- package as Debian artifact
- prepare ISO/bootstrap path
- switch dashboard serving from dev mode to production static assets

## 17. Acceptance Criteria

The desktop environment is considered acceptable for MVP when:

1. A fresh Ubuntu or Debian VM can run the setup script successfully
2. XFCE loads into a minimal workspace shell
3. Desktop icons are hidden
4. Traditional application menu is not central to the workflow
5. Browser app mode opens the XWorkspace console automatically
6. Dashboard can read local service health
7. Reset script can roll back XWorkspace-specific desktop changes
8. Standard terminal, browser, and file manager behavior remains intact

## 18. Current Repository Direction

As of this design draft, `xworkspace-console` should be treated as:

- the canonical merged repo
- the source of desktop shell templates
- the source of systemd service templates
- the source of the Go local API
- the source of the React dashboard

This design supersedes the earlier split between a Flutter console repo, a static portal concept, and a separate desktop skeleton.
