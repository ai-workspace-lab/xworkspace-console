[🇺🇸 English](../../README.md) | [🇨🇳 中文](../../README.zh.md)

## 1. Delivery Goals and Acceptance Criteria

### 1.1 Overall Goals

1. Make necessary adjustments and submit them separately to the three repositories without expanding the scope of modifications or making large-scale refactors.
2. Use `scripts/setup-ai-workspace-all-in-one.sh` to deploy AI Workspace to `root@acp-bridge.onwalk.net`.
3. `xworkmate bridge` will uniformly use `acp-bridge.onwalk.net` as the external domain, and it is the **default and only public** service.
4. Deliver a complete AI Workspace Runtime: versions of `xfce_desktop` + NodeJS + Playwright are all fully controlled.
5. Runtime modes `docker / k3s / systemd` are optional and freely composable (`docker` and `k3s` are mutually exclusive, `docker + systemd` can be combined).
6. Role split: `roles/vhosts/xfce_xrdp_minimal` → `roles/vhosts/xfce_desktop_minimal_runtime` + `roles/vhosts/remote_desktop_xrdp_server`.
7. After the deployment script finishes, it will output a unified deployment summary **aimed at the end user**, and important authentication information will be **displayed only once**.

### 1.2 Acceptance Criteria (Definition of Done)

- [ ] Code submissions for all three repositories are completed, providing their respective Commit Hashes.
- [ ] `setup-ai-workspace-all-in-one.sh` executes successfully in remote exec mode on the target host (no rsync, repositories are pulled from GitHub by the remote host).
- [ ] Bridge uses `acp-bridge.onwalk.net` externally; other services are not public by default.
- [ ] The script finishes by outputting a unified deployment summary: access entry points, one-time credentials, running status of each service, and available Agent CLIs.
- [ ] Versions of `xfce_desktop / NodeJS / Playwright` can all be found and pinned in a single source of truth (role defaults).
- [ ] Two consecutive installations on the same host both succeed; the second execution does not generate new credentials, does not redownload the same release packages, and waits for concurrent APT/dpkg operations rather than breaking them.

---

## 5. Detailed Change List

### 5.1 Role Split: `xfce_xrdp_minimal` → Two Roles

Split by responsibility, **file-by-file mapping**, preserving behavior; `setup-xfce-xrdp.yaml` is modified to sequentially compose the two new roles.

**`roles/vhosts/xfce_desktop_minimal_runtime` (Desktop Runtime)**

| Source | Destination | Description |
|---|---|---|
| `tasks/install.yml` (only desktop packages: `xfce4-session/xfwm4/xfdesktop4/xfce4-panel/xfce4-terminal/dbus-x11/fonts-noto-cjk/xserver-xorg-core`) | `tasks/install.yml` | Removed `xorgxrdp/xrdp` packages and xrdp service start |
| `tasks/browser.yml` (Fixed version of Google Chrome) | `tasks/browser.yml` | Kept as is |
| New `tasks/runtime.yml` | NodeJS + Playwright (references existing fixed version variables from `nodejs` / `ai_agent_runtime`) | Version-controlled single source of truth |
| `defaults/main.yml` (desktop/chrome/node/playwright version variables) | `defaults/main.yml` | See §5.2 version table |

**`roles/vhosts/remote_desktop_xrdp_server` (Remote Desktop XRDP Service)**

| Source | Destination | Description |
|---|---|---|
| `tasks/install.yml` (`xorgxrdp/xrdp`, ssl-cert group, daemon-reload, enable/start, unit validation/fail) | `tasks/install.yml` | XRDP service layer |
| `tasks/config.yml` (User/password RDP authentication, `.xsession`, xfconf directory) | `tasks/config.yml` | RDP session glue |
| `handlers/main.yml` (Restart xrdp / sesman) | `handlers/main.yml` | Kept as is |
| `vars/main.yml` (`xfce_xrdp_services` etc.) + `xfce_rdp_port/xfce_enable_ufw` | `defaults`/`vars` | Ports/ufw |

**Composition Point `setup-xfce-xrdp.yaml`:**

```yaml
- name: Deploy XFCE desktop + optional XRDP (Optional)
  hosts: all
  become: true
  vars:
    xworkspace_console_enable_xrdp: false
  tasks:
    - include_role: { name: roles/vhosts/xfce_desktop_minimal_runtime }
    - include_role: { name: roles/vhosts/remote_desktop_xrdp_server }
      when: xworkspace_console_enable_xrdp | bool
```

> Old role `roles/vhosts/xfce_xrdp_minimal`: Delete it after the split is complete and all references have been switched (the only current reference is `setup-xfce-xrdp.yaml`).

### 5.2 Version Pinning Table (Single Source of Truth)

| Component | Variable | Current | Target | File |
|---|---|---|---|---|
| OpenClaw | `gateway_openclaw_required_version` | `2026.5.28` | `2026.6.1` | `roles/vhosts/gateway_openclaw/defaults/main.yml:23` |
| Vault | `vault_version` (env default) | `1.20.4` | `1.21.4` | `roles/vhosts/vault/vars/main.yml:6` |
| Hermes | `acp_hermes_version` (New) | None | `0.15` | `roles/vhosts/acp_server_hermes/defaults/main.yml` |
| QMD | `qmd_version` / `qmd_source_repo` (New) | None | From `ai-workspace-services/qmd` | `roles/vhosts/qmd/defaults/main.yml` |
| LiteLLM | `litellm_version` / `litellm_source_repo` (New) | None | From `ai-workspace-services/litellm` | `roles/vhosts/litellm/defaults/main.yml` |
| NodeJS | `nodejs_version` / `ai_agent_runtime_nodejs_version` | `22.x` / `24.x` | Pin to specific minor version | `roles/vhosts/nodejs/defaults` + `roles/ai_agent_runtime/defaults` |
| Playwright | `ai_agent_runtime_playwright_version` (New/pinned) | No explicit | Pinned | `roles/ai_agent_runtime/defaults/main.yml` |
| Google Chrome | `xfce_google_chrome_version` | `148.0.7778.167-1` | Keep pinned | Runtime role `defaults/main.yml` |
| XFCE | `xfce_packages` | List | Keep (pinned by apt distro) | Runtime role `defaults/main.yml` |

### 5.3 Bridge External Domain (Custom Parameter, Not Hardcoded Default)

- **`acp-bridge.onwalk.net` is a host-specific custom parameter**, passed via `XWORKMATE_BRIDGE_DOMAIN` during deployment, **not hardcoded as a role default**.
- Implementation key points (minimal changes): Ensure `XWORKMATE_BRIDGE_DOMAIN` is correctly passed through from the bootstrap script → playbook → `roles/vhosts/xworkmate_bridge`. The existing env override chain already supports this: `XWORKMATE_BRIDGE_DOMAIN` → `ai_workspace_public_domain` (`SERVER_DOMAIN/ACP_BRIDGE_DOMAIN/BRIDGE_DOMAIN`).
- The neutral fallback default value in `roles/vhosts/xworkmate_bridge/defaults/main.yml:47` (`xworkmate-bridge.svc.plus`) **remains unchanged**—it serves only as a fallback when no explicit parameter is passed; the target host specifies the real domain via `XWORKMATE_BRIDGE_DOMAIN=acp-bridge.onwalk.net`.
- Acceptance only requires "Bridge uses the specified domain", which is met by the custom parameter, requiring no changes to role defaults.

### 5.4 Deployment Script Unified Summary (`setup-ai-workspace-all-in-one.sh`)

At the end of the existing script (in the console repository, roughly 39KB), **append** a block for summary rendering (probing real-time host status, without hardcoding), structured as follows:

```
================ AI Workspace Deployment Summary ================
[Access Entry]
  Workspace Portal (Console) : http://127.0.0.1:17000      (Local)
  XWorkMate Bridge           : https://acp-bridge.onwalk.net   ← Only Public
[One-time Credentials] (displayed once only)
  AI_WORKSPACE_AUTH_TOKEN     : ********
  Vault root token            : ********
[Service Status]
  Portal / Bridge / OpenClaw / QMD / Hermes / PostgreSQL / Vault / LiteLLM : active/inactive
[Agent CLI]
  opencode / gemini / codex / claude : <version | Missing>
======================================================
```

- Status probing reuses the `generate-status.py` logic from the console and the `validate.yml` health checks of each role (`systemctl is-active` + `curl` health endpoints).
- Credentials "displayed once only": The summary reads the tokens from the persisted token files and prompts the user to save them; the script does not repeatedly print them.

### 5.5 all-in-one Aggregation Chain Adjustments

- Add the §4.3 runtime mode `assert` guard play at the top.
- Remove the Step 10 independent `deploy_agent_hermes.yml` import (deduplication, see §4.2).
- The rest of the import order remains unchanged.

---
