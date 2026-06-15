# XWorkspace Console Features

This document summarizes the user-facing and operator-facing features of XWorkspace Console. It is intended as the detailed feature reference linked from the homepage README.

## 1. Product Scope

XWorkspace Console is a local AI workspace control plane that combines:

- a React dashboard for workspace navigation
- a Go API for service and health status
- systemd user services for runtime orchestration
- XFCE and XDG templates for desktop integration
- browser-based access to local AI tools and services

The console is optimized for local-first use, with the browser acting as the primary operator surface.

## 2. Homepage Experience

The homepage acts as the central control surface:

- shows the workspace overview
- surfaces service health and runtime state
- provides quick access to services and tabs
- keeps the layout compact and operational
- supports image and video artifact review as custom tabs

The homepage preview in the README is the canonical visual entry point.

## 3. Tab System

Tabs are the main way to navigate between workspace areas.

### Built-in tabs

- `Workspace`
  - main overview and dashboard entry
- `OpenClaw`
  - gateway access and channels view
- `LiteLLM`
  - model routing and provider administration
- `Vault`
  - secrets and auth management
- `Terminal`
  - embedded local shell access

### Custom tabs

The console can also host custom tabs for artifact-oriented workflows. This is where image and video workflows fit naturally.

That tab model lets the workspace keep review, navigation, and runtime actions in one place instead of spreading them across separate applications.

## 4. Image and Video Workflows

Image and video workflows are first-class console use cases.

They are designed to support:

- previewing generated or imported media
- reviewing outputs alongside service status
- switching between artifacts and runtime tools without leaving the console shell
- keeping media-centric work inside the same operational workspace

## 5. Service Integration

The console integrates with local runtime services and exposes them as part of the workspace experience.

### Core services

- Console dashboard
- Go status API
- Bridge control plane
- OpenClaw Gateway
- LiteLLM UI/API
- Vault
- ttyd terminal

### Status surface

The dashboard can consume:

- `/health`
- `/services`
- `/metrics/simple`

This keeps the UI responsive while still reflecting the current local runtime state.

## 6. Desktop Integration

The repository includes desktop support files for:

- XFCE session and panel configuration
- XDG autostart launchers
- systemd user units
- Chrome or Chromium app-mode launch paths
- local console startup scripts

This makes the console easy to start automatically and easy to align with a minimal desktop shell.

## 7. Access Model

The console is designed for local-first access.

Common access points include:

- `http://127.0.0.1:17000` for the main console
- `http://127.0.0.1:8788` for the Go API
- `http://127.0.0.1:18789` for OpenClaw
- `http://127.0.0.1:4000/ui` for LiteLLM
- `http://127.0.0.1:8200/ui` for Vault
- `http://127.0.0.1:7681` for the embedded terminal

The port plan is documented separately in [`docs/operations/service-port-plan.md`](./operations/service-port-plan.md).

## 8. Repository Roles

The repository is split into clear functional areas:

- `dashboard/`
  - user interface
- `api/`
  - status and health endpoints
- `config/`
  - desktop and service configuration
- `scripts/`
  - install, start, reset, and launch helpers
- `docs/`
  - architecture, setup, operations, and feature references

## 9. What This Repo Is Not

XWorkspace Console is not intended to be:

- a full desktop environment replacement
- a custom compositor project
- a generic web app shell with no service orchestration
- a marketing site without runtime integration

It is a focused control plane for AI workspace operations.
