[🇺🇸 English](../../README.md) | [🇨🇳 中文](../../README.zh.md)

# XWorkspace Architecture

XWorkspace is an AI Workspace Shell built on top of standard Linux, systemd, Chrome / Chromium, and local runtime services.

The core idea is simple:

Do not expose a traditional Linux desktop to the user.
Use Chrome / Chromium as the Desktop Shell, and use a local AI Workspace Portal as the main entry point.

XWorkspace is not trying to build a full operating system from scratch. It keeps the Linux base stable and standard, while replacing the user-facing desktop experience with an AI-native workspace.

⸻

## 1. Design Goals

XWorkspace is designed around the following principles:

### 1. Chrome / Chromium as Desktop Shell
    The user enters the workspace through Chrome / Chromium instead of XFCE, GNOME, or a traditional desktop environment.

### 2. Portal-first user experience
    The main workspace UI is a local web portal, usually exposed at: http://localhost:17000

3. Minimal traditional desktop exposure
    XWorkspace avoids exposing panels, desktop icons, file manager desktops, or traditional application menus.
4. Local-first runtime services
    Core services run locally through user-level systemd services.
5. AI Agent oriented workflow
    The workspace is optimized for Agent, Terminal, Browser Use, Computer Use, Model Gateway, Vault, Workflow, Skill, and Plugin scenarios.
6. Composable service architecture
    Each runtime capability is an independent service that can be started, stopped, upgraded, or replaced separately.

⸻

## 2. High-level Architecture

```i11·
┌──────────────────────────────────────────────┐
│ Layer 1：Chrome / Chromium Desktop Shell      │
│                                              │
│ - App mode / kiosk mode                       │
│ - Fullscreen workspace entry                  │
│ - Replaces traditional Linux desktop entry    │
│ - Opens http://localhost:17000                │
└──────────────────────┬───────────────────────┘
                       ↓
┌──────────────────────────────────────────────┐
│ Layer 2：AI Workspace Portal                  │
│                                              │
│ - Dashboard                                   │
│ - App launcher                                │
│ - Runtime status                              │
│ - Agent sessions                              │
│ - Terminal / VSCode / Files                   │
│ - Model / Vault / Workflow entry              │
└──────────────────────┬───────────────────────┘
                       ↓
┌──────────────────────────────────────────────┐
│ Layer 3：Core Services                        │
│                                              │
│ - Bridge                                      │
│ - Agent Runtime / Gateway                     │
│ - LiteLLM Proxy                               │
│ - Vault / Vault Proxy                         │
│ - ttyd                                        │
│ - Status Generator                            │
│ - Local API / SSE / WebSocket                 │
└──────────────────────┬───────────────────────┘
                       ↓
┌──────────────────────────────────────────────┐
│ Layer 4：App / Extra Services                 │
│                                              │
│ - Agent                                       │
│ - Skill                                       │
│ - Workflow                                    │
│ - Plugin                                      │
│ - Computer Use                                │
│ - Browser Use                                 │
│ - Code Server                                 │
│ - File Browser                                │
└──────────────────────────────────────────────┘
```

## 3. Runtime Flow

Linux boot
  ↓
User-level systemd session
  ↓
Core services start
  ↓
xworkspace-portal.service starts local portal
  ↓
xworkspace-shell.service starts Chrome / Chromium
  ↓
Chrome / Chromium opens http://localhost:17000
  ↓
User enters AI Workspace Portal
  ↓
Portal talks to Bridge, Agent, LiteLLM, Vault, ttyd, and extra services

## 4. Core Concept

Traditional Linux desktop:
Desktop Environment
  ├─ Panel
  ├─ File Manager
  ├─ Terminal
  ├─ Browser
  ├─ App Menu
  └─ Settings

XWorkspace desktop

Chrome / Chromium Desktop Shell
  └─ AI Workspace Portal
      ├─ Agent Console
      ├─ Terminal
      ├─ VSCode / Code Server
      ├─ Files
      ├─ Model Gateway
      ├─ Vault Secrets
      ├─ Runtime Status
      ├─ Workflow Runner
      ├─ Plugin Center
      ├─ Browser Use
      └─ Computer Use


## 5. Display Stack Strategy

XWorkspace avoids supporting the traditional X11 desktop experience as a product surface.
However, Chrome / Chromium still needs a display stack.
Recommended evolution path:

Stage 1:

Use XFCE or a lightweight desktop session, but hide traditional desktop components and only expose Chrome / Chromium Shell.

Stage 2:

Replace XFCE with a minimal window manager. Only Chrome / Chromium is launched as the visible workspace shell.

Stage 3:

Move to Wayland / Weston / Cage mode. Chrome / Chromium becomes the only user-facing shell.


## Access & Exposure Strategy

XWorkspace follows a secure-by-default access strategy.

By default, XWorkspace does not expose the full AI Workspace Portal, WebRTC Desktop, ttyd, LiteLLM, Vault, or other internal services directly to the public Internet.

The default public entry should be limited to: https://xworkmate-bridge.example.com

This endpoint is protected by an access token in the early stage and should evolve to JWT-based authentication in future versions.

Default Access Model

Public Internet
  ↓
https://xworkmate-bridge.example.com
  ↓
Token / Future JWT Auth
  ↓
XWorkmate Bridge
  ↓
Local Core Services

The AI Workspace Portal remains local by default:

Chrome / Chromium Desktop Shell
  ↓
http://localhost:17000
  ↓
AI Workspace Portal


Not exposed by default:

- AI Workspace Portal
- WebRTC Desktop
- ttyd
- LiteLLM
- Vault
- OpenClaw Gateway
- Internal status endpoints
- Plugin / workflow services

Advanced User Mode

Advanced users may choose to expose additional services, but they should do so explicitly and with stronger access controls.
Recommended advanced exposure requirements:

- HTTPS

- MFA
- JWT authentication
- IP allowlist, optional
- Reverse proxy access policy
- Audit logs
- Rate limiting
- Separate subdomains for sensitive services
