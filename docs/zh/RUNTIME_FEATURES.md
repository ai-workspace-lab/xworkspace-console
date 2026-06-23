[🇺🇸 English](../../README.md) | [🇨🇳 中文](../../README.zh.md)

## 1. 交付目标与验收标准

### 1.1 总体目标

1. 在不扩大修改范围、不做大规模重构的前提下，完成必要调整并分别提交三个仓库。
2. 使用 `scripts/setup-ai-workspace-all-in-one.sh` 将 AI Workspace 部署到 `root@acp-bridge.onwalk.net`。
3. `xworkmate bridge` 统一使用 `acp-bridge.onwalk.net` 作为对外域名，且是**唯一默认公开**的服务。
4. 交付一个完整的 AI Workspace Runtime：`xfce_desktop` + NodeJS + Playwright 全部版本受控。
5. 运行模式 `docker / k3s / systemd` 可选、可自由组合（`docker` 与 `k3s` 互斥，`docker + systemd` 可组合）。
6. 角色拆分：`roles/vhosts/xfce_xrdp_minimal` → `roles/vhosts/xfce_desktop_minimal_runtime` + `roles/vhosts/remote_desktop_xrdp_server`。
7. 部署脚本结束后输出一份**面向最终用户**的统一部署摘要，重要认证信息**仅显示一次**。

### 1.2 验收标准（Definition of Done）

- [ ] 三个仓库完成代码提交，提供各自 Commit Hash。
- [ ] `setup-ai-workspace-all-in-one.sh` 在目标主机以远程 exec 模式执行成功（无 rsync，仓库由远程主机自 GitHub pull）。
- [ ] Bridge 对外使用 `acp-bridge.onwalk.net`，其余服务默认不公开。
- [ ] 脚本结束输出统一部署摘要：访问入口、一次性凭据、各服务运行状态、可用 Agent CLI。
- [ ] `xfce_desktop / NodeJS / Playwright` 版本均可在单一来源（role defaults）查到并被固定。
- [ ] 同一主机连续执行两次安装均成功，第二次执行不生成新凭据、不重复下载同一 release 包，并等待而非破坏并发 APT/dpkg 操作。

---

## 5. 详细变更清单

### 5.1 角色拆分：`xfce_xrdp_minimal` → 两个角色

按职责拆分，**逐文件映射**，行为不变；`setup-xfce-xrdp.yaml` 改为顺序组合两个新角色。

**`roles/vhosts/xfce_desktop_minimal_runtime`（桌面运行时）**

| 来源 | 去向 | 说明 |
|---|---|---|
| `tasks/install.yml`（仅桌面包：`xfce4-session/xfwm4/xfdesktop4/xfce4-panel/xfce4-terminal/dbus-x11/fonts-noto-cjk/xserver-xorg-core`） | `tasks/install.yml` | 移除 `xorgxrdp/xrdp` 包与 xrdp 服务启动 |
| `tasks/browser.yml`（Google Chrome 固定版） | `tasks/browser.yml` | 原样保留 |
| 新增 `tasks/runtime.yml` | NodeJS + Playwright（引用既有 `nodejs` / `ai_agent_runtime` 的固定版本变量） | 版本受控单一来源 |
| `defaults/main.yml`（desktop/chrome/node/playwright 版本变量） | `defaults/main.yml` | 见 §5.2 版本表 |

**`roles/vhosts/remote_desktop_xrdp_server`（远程桌面 XRDP 服务）**

| 来源 | 去向 | 说明 |
|---|---|---|
| `tasks/install.yml`（`xorgxrdp/xrdp`、ssl-cert 组、daemon-reload、enable/start、unit 校验/fail） | `tasks/install.yml` | XRDP 服务层 |
| `tasks/config.yml`（用户/口令 RDP 认证、`.xsession`、xfconf 目录） | `tasks/config.yml` | RDP 会话粘合 |
| `handlers/main.yml`（Restart xrdp / sesman） | `handlers/main.yml` | 原样保留 |
| `vars/main.yml`（`xfce_xrdp_services` 等）+ `xfce_rdp_port/xfce_enable_ufw` | `defaults`/`vars` | 端口/ufw |

**组合点 `setup-xfce-xrdp.yaml`：**

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

> 旧角色 `roles/vhosts/xfce_xrdp_minimal`：拆分完成且引用全部切换后删除（当前唯一引用即 `setup-xfce-xrdp.yaml`）。

### 5.2 版本固定表（单一来源）

| 组件 | 变量 | 当前 | 目标 | 文件 |
|---|---|---|---|---|
| OpenClaw | `gateway_openclaw_required_version` | `2026.5.28` | `2026.6.1` | `roles/vhosts/gateway_openclaw/defaults/main.yml:23` |
| Vault | `vault_version`（env 默认值） | `1.20.4` | `1.21.4` | `roles/vhosts/vault/vars/main.yml:6` |
| Hermes | `acp_hermes_version`（新增） | 无 | `0.15` | `roles/vhosts/acp_server_hermes/defaults/main.yml` |
| QMD | `qmd_version` / `qmd_source_repo`（新增） | 无 | 取自 `ai-workspace-services/qmd` | `roles/vhosts/qmd/defaults/main.yml` |
| LiteLLM | `litellm_version` / `litellm_source_repo`（新增） | 无 | 取自 `ai-workspace-services/litellm` | `roles/vhosts/litellm/defaults/main.yml` |
| NodeJS | `nodejs_version` / `ai_agent_runtime_nodejs_version` | `22.x` / `24.x` | 固定明确小版本 | `roles/vhosts/nodejs/defaults` + `roles/ai_agent_runtime/defaults` |
| Playwright | `ai_agent_runtime_playwright_version`（新增/固定） | 无显式 | 固定 | `roles/ai_agent_runtime/defaults/main.yml` |
| Google Chrome | `xfce_google_chrome_version` | `148.0.7778.167-1` | 保持固定 | 运行时角色 `defaults/main.yml` |
| XFCE | `xfce_packages` | 列表 | 保持（apt 发行版固定） | 运行时角色 `defaults/main.yml` |

### 5.3 Bridge 对外域名（自定义参数，非硬编码默认）

- **`acp-bridge.onwalk.net` 是 host-specific 的自定义参数**，经 `XWORKMATE_BRIDGE_DOMAIN` 在部署时传入，**不写死为 role 默认值**。
- 实现要点（最小改动）：确保 `XWORKMATE_BRIDGE_DOMAIN` 经 bootstrap 脚本 → playbook → `roles/vhosts/xworkmate_bridge` 正确透传。现有 env 覆盖链已支持：`XWORKMATE_BRIDGE_DOMAIN` → `ai_workspace_public_domain`（`SERVER_DOMAIN/ACP_BRIDGE_DOMAIN/BRIDGE_DOMAIN`）。
- `roles/vhosts/xworkmate_bridge/defaults/main.yml:47` 的中性回退默认值（`xworkmate-bridge.svc.plus`）**保持不变**——仅作为未显式传参时的兜底；目标主机通过 `XWORKMATE_BRIDGE_DOMAIN=acp-bridge.onwalk.net` 指定真实域名。
- 验收只要求“Bridge 使用指定域名”，由自定义参数满足，无需改动 role 默认。

### 5.4 部署脚本统一摘要（`setup-ai-workspace-all-in-one.sh`）

在现有脚本（console 仓库，约 39KB）末尾**追加**一段摘要渲染（探测主机实时状态，不硬编码），结构如下：

```
================ AI Workspace 部署摘要 ================
[访问入口]
  Workspace Portal (Console) : http://127.0.0.1:17000      (本地)
  XWorkMate Bridge           : https://acp-bridge.onwalk.net   ← 唯一公开
[一次性凭据]（仅显示一次）
  AI_WORKSPACE_AUTH_TOKEN     : ********
  Vault root token            : ********
[服务状态]
  Portal / Bridge / OpenClaw / QMD / Hermes / PostgreSQL / Vault / LiteLLM : active/inactive
[Agent CLI]
  opencode / gemini / codex / claude : <version | 缺失>
======================================================
```

- 状态探测复用 console 的 `generate-status.py` 逻辑与各 role 的 `validate.yml` 健康检查（`systemctl is-active` + `curl` 健康端点）。
- 凭据“仅显示一次”：摘要从已落盘的 token 文件读取展示后，提示用户保存；脚本不重复打印。

### 5.5 all-in-one 聚合链调整

- 顶部新增 §4.3 运行模式 `assert` 守卫 play。
- 移除步骤 10 独立 `deploy_agent_hermes.yml` 导入（去重，见 §4.2）。
- 其余导入顺序保持不变。

---
