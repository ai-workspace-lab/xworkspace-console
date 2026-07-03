[🇺🇸 English](../../../README.md) | [🇨🇳 中文](../../../README.zh.md)

# XWorkspace Console Service Port Plan

Date: 2026-06-07

This plan is based on the live host inspection of `ubuntu@xworkmate-bridge.svc.plus`
(`jp-xhttp-contabo.svc.plus`) and the local XWorkspace Console repository state.

## Canonical Endpoint Map

| Component | Bind | Port | URL | Owner | Notes |
| --- | --- | ---: | --- | --- | --- |
| XWorkspace Console | `127.0.0.1` | `17000` | `http://127.0.0.1:17000` | `xworkspace-console.service` | Canonical dashboard endpoint. Avoids macOS `ControlCenter` conflicts on `7000`. |
| XWorkspace Status API | `127.0.0.1` | `8788` | `http://127.0.0.1:8788` | `xworkspace-api.service` | Go API for `/health`, `/services`, `/metrics/simple`. |
| XWorkmate Bridge | `127.0.0.1` | `8787` | `http://127.0.0.1:8787` | `xworkspace-bridge.service` / live `xworkmate-bridge.service` | Keep reserved for bridge control plane. Do not reuse for dashboard. |
| OpenClaw Gateway | `127.0.0.1` | `18789` | `http://127.0.0.1:18789/channels` | `xworkspace-openclaw.service` / live `openclaw-gateway.service` | OpenClaw UI and gateway entry. |
| LiteLLM | `127.0.0.1` | `4000` | `http://127.0.0.1:4000/ui` | `xworkspace-litellm.service` | Live host returns HTTP 200 after redirect. |
| X Memory Hub | `127.0.0.1` | `8790` | `http://127.0.0.1:8790/healthz` | `x-memory-hub.service` / macOS `plus.svc.xworkspace.x-memory-hub` | Development version (tracks `main`); REST + MCP on one port. |
| Vault | `0.0.0.0` or `127.0.0.1` | `8200` | `http://127.0.0.1:8200` | `xworkspace-vault.service` / system Vault | Live host exposes Vault on `0.0.0.0:8200`; tighten to loopback later if no remote clients need it. |
| Embedded Terminal | `127.0.0.1` | `7681` | `http://127.0.0.1:7681` | `ttyd.service` or `xworkspace-ttyd.service` | Use only one owner. Live host already has system `ttyd.service`; user `xworkspace-ttyd.service` fails due port conflict. |
| Legacy Portal | `0.0.0.0` | `7000` | `http://127.0.0.1:7000` | `xworkspace-portal.service` | Deprecated. Replace with Console on `17000`. |

## Live Host Findings

- `xworkspace-portal.service` is active on `0.0.0.0:7000` using `python3 -m http.server 7000`.
- `xworkspace-chrome.service` currently opens `--app=http://localhost:7000`.
- `xworkspace-console.service` exists but is inactive and still points to the old script model.
- `xworkmate-bridge.service` is active on `127.0.0.1:8787`.
- `openclaw-gateway.service` is active on `127.0.0.1:18789`.
- `xworkspace-litellm.service` is active on `127.0.0.1:4000`.
- Vault is active on `0.0.0.0:8200`.
- System `ttyd.service` is active on `127.0.0.1:7681`.
- User `xworkspace-ttyd.service` is auto-restarting because `7681` is already occupied.

## Migration Order

1. Deploy the React Console to `~/xworkspace-console/dashboard`.
2. Replace `xworkspace-console.service` with a long-running service on `127.0.0.1:17000`.
3. Change Chrome app mode to `http://127.0.0.1:17000` and depend on `xworkspace-console.service`.
4. Disable `xworkspace-portal.service` after Console passes health checks.
5. Keep `xworkmate-bridge.service` on `127.0.0.1:8787`.
6. Keep `ttyd` on `127.0.0.1:7681`; do not start `xworkspace-ttyd.service` when system `ttyd.service` is already active.
7. Keep LiteLLM, Vault, and OpenClaw on their existing live ports.

## Collision Rules

- Never assign Console to `7000`; macOS may reserve it and the live host already uses it for the deprecated portal.
- Never assign Console to `8787`; that is the bridge control-plane port.
- Treat `7681` as singleton terminal ownership; system `ttyd.service` wins if present.
- Prefer loopback binds for all control-plane services unless a reverse proxy explicitly exposes them.
