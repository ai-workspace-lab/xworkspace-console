# AI Workspace Runtime 交付规划

> 目标：把 `setup-ai-workspace-all-in-one.sh` 从“一组分散的基础设施 Playbook”收敛为一个**可直接使用的 AI Workspace Runtime 产品**——版本受控、运行模式可组合、对外仅暴露 Bridge、部署完成后输出一次性统一摘要。
>
> 本文是落地前的详细规划（设计 + 变更清单 + 提交/部署/验收方案）。实现阶段严格按本文执行，不扩大修改范围、不做大规模重构、优先复用现有实现。

- 状态：规划已定稿，待实现
- 影响仓库：`ai-workspace-infra/playbooks`、`ai-workspace-lab/xworkspace-console`、`ai-workspace-lab/xworkspace-core-skills`
- 目标主机：`root@acp-bridge.onwalk.net`
- 对外默认域名（唯一公开服务）：`acp-bridge.onwalk.net`

## TODO

- [x] 等待并核对 `xworkspace-console` 的离线包 GitHub Actions 发布链路，确认 `publish-release` 完整结束且 release 产物上传成功。
- [ ] 继续核对 `root@acp-bridge.onwalk.net` 的远程部署进度，确认 `setup-ai-workspace-all-in-one.sh` 最终完成并输出统一摘要。
- [x] `setup-ai-workspace-all-in-one.sh` 在目标主机上优先使用离线安装包加速部署，减少在线拉取与安装耗时。
- [ ] 验证 `setup-ai-workspace-all-in-one.sh` 幂等性：同一主机连续执行两次均成功，复用凭据、离线包缓存与已导入镜像，并安全等待部署/APT 锁。
- [ ] 完成最终验收核对：Bridge 对外可达、其余服务默认仅本地监听、`acp-codex` / `opencode` / `gemini` / `hermes` / `qmd` / `litellm` 状态正常。
- [ ] 记录最终提交哈希与远端验证结果，回填到本计划的交付结果部分。

---

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

## 2. 部署执行模型（远程 exec / GitHub pull）

- `scripts/setup-ai-workspace-all-in-one.sh` 运行**在远程主机上**，全程 remote exec 模式。
- **不使用 rsync**；所需仓库由远程主机直接从 GitHub `pull`：
  - Playbooks：`https://github.com/ai-workspace-infra/playbooks.git`
  - Core Skills：`https://github.com/ai-workspace-lab/xworkspace-core-skills.git`
  - Console（脚本自身所在仓库）：`https://github.com/ai-workspace-lab/xworkspace-console.git`
  - QMD：`https://github.com/ai-workspace-services/qmd.git`
  - LiteLLM：`https://github.com/ai-workspace-services/litellm.git`
- 含义：**本地提交必须推送到上述 GitHub 仓库后，远程部署才能拉到改动**。

> ⚠️ 注意仓库地址不一致：playbooks 本地 `origin` 当前为 `git@github.com:x-evor/playbooks.git`，而部署权威源是 `ai-workspace-infra/playbooks`。实现阶段需将脚本中的 pull 源对齐到 `ai-workspace-infra/playbooks`，并把提交推送到该仓库。

### 2.1 环境变量接口契约（权威）

bootstrap 入口固定为 console 仓库的原始脚本，所有暴露/安全/可选桌面行为均通过 `bash -` 前的环境变量控制。

**标准安装**（默认安全本地工作区，仅需一个统一 token）：

```bash
curl -sfL https://raw.githubusercontent.com/ai-workspace-lab/xworkspace-console/main/scripts/setup-ai-workspace-all-in-one.sh | bash -
```

**全部参数（默认值与推荐用法）：**

| 变量 | 默认 | 推荐用法 |
|---|---|---|
| `TOKEN` | 生成或复用 | 为 Bridge / Portal / LiteLLM / OpenClaw / Vault 设置**统一**认证 token |
| `AI_WORKSPACE_SECURITY_LEVEL` | `standard` | 公网/半公网主机使用 `strict` |
| `XWORKMATE_BRIDGE_PUBLIC_ACCESS` | `true` | Bridge 为默认唯一公开服务；如需关闭对外访问可显式设 `false` |
| `XWORKMATE_BRIDGE_DOMAIN` | host-specific | 设置 Bridge 公网域名，例如 `acp-bridge.onwalk.net` |
| `XWORKSPACE_CONSOLE_PUBLIC_ACCESS` | `false` | 仅当 Portal 必须公开时开启；本地优先更安全 |
| `XWORKSPACE_CONSOLE_ENABLE_XRDP` | `false` | 仅当需要远程桌面访问时开启 |
| `GATEWAY_OPENCLAW_PUBLIC_ACCESS` | `false` | 除非 OpenClaw 必须直接暴露，保持 false |
| `VAULT_PUBLIC_ACCESS` | `false` | 常规部署保持 false |
| `LITELLM_API_CADDY_STRICT_WHITELIST` | `false` | strict 且 LiteLLM 经 Caddy 暴露时开启 |

**进阶安装示例：**

```bash
curl -sfL https://raw.githubusercontent.com/ai-workspace-lab/xworkspace-console/main/scripts/setup-ai-workspace-all-in-one.sh | \
  AI_WORKSPACE_SECURITY_LEVEL=strict \
  XWORKSPACE_CONSOLE_ENABLE_XRDP=true \
  XWORKSPACE_CONSOLE_PUBLIC_ACCESS=true \
  XWORKMATE_BRIDGE_PUBLIC_ACCESS=true \
  GATEWAY_OPENCLAW_PUBLIC_ACCESS=false \
  VAULT_PUBLIC_ACCESS=false \
  LITELLM_API_CADDY_STRICT_WHITELIST=true \
  TOKEN="your-unified-auth-token" \
  bash -
```

**目标主机（ACP Bridge）示例：**

```bash
curl -sfL https://raw.githubusercontent.com/ai-workspace-lab/xworkspace-console/main/scripts/setup-ai-workspace-all-in-one.sh | \
  XWORKMATE_BRIDGE_DOMAIN=acp-bridge.onwalk.net \
  XWORKMATE_BRIDGE_PUBLIC_ACCESS=true \
  AI_WORKSPACE_SECURITY_LEVEL=strict \
  bash -
```

> 关键校准：`XWORKMATE_BRIDGE_PUBLIC_ACCESS` 默认 **`true`**——Bridge 是**默认唯一公开**的服务（域名经 `XWORKMATE_BRIDGE_DOMAIN` 自定义传入）；其余服务（Console/OpenClaw/Vault/QMD/Hermes/PG/LiteLLM）默认 `false`，保持 `127.0.0.1` 本地监听。如需关闭 Bridge 对外访问，显式设 `XWORKMATE_BRIDGE_PUBLIC_ACCESS=false`。`TOKEN` 输出务必私密保存——不得拷入前端源码或提交到 Git。

### 2.2 预期最终输出（部署摘要）

部署成功后，脚本将**一次性**打印部署域名与 token，随后报告各服务运行状态：

- AI Workspace 域名与 token（仅显示一次）
- OpenClaw
- QMD
- PostgreSQL
- Vault
- Workspace Portal / Console
- LiteLLM
- Hermes
- Agent CLI：opencode、gemini、codex、claude

### 2.3 本地 macOS 校验模式

在 macOS 上脚本默认进入**本地校验模式**，在 `http://127.0.0.1:17000` 启动 Portal。若因端口占用校验失败，先停止已有本地服务或在干净会话中重试。

---

## 3. 现状分析：角色层级关系

`setup-ai-workspace-all-in-one.sh`（位于 console 仓库）在目标主机引导后，运行 `setup-ai-workspace-all-in-one.yml`（位于 playbooks 仓库）。其按导入顺序的角色层级：

```
setup-ai-workspace-all-in-one.sh            [repo: xworkspace-console/scripts]
  └─ ansible-playbook setup-ai-workspace-all-in-one.yml   [repo: playbooks]
     ├─1 setup-nodejs.yml          → role roles/vhosts/nodejs        NodeJS(22.x)+yarn
     ├─2 setup-xworkspace-console.yaml   WORKSPACE PORTAL/CONSOLE（内联 task，无 role）
     │      apt: caddy,xfce4,python3,golang-go,google-chrome-stable,ttyd
     │      git clone console → npm build；systemd --user: console(:17000)/api(:8788)/ttyd(:7681)/status.timer
     │      Caddy 公网站点 workspace.svc.plus   ⚠ 标准模式下也公开
     ├─3 setup-ai-agent-skills.yml → role roles/ai_agent_runtime    AI WORKSPACE RUNTIME 核心
     │      NodeJS(24.x)+Playwright；Agent CLI: opencode/gemini/codex/claude；Python/browser/docs/fonts
     │      └─ role agent_skills → 注入 xworkspace-core-skills 市场技能
     ├─4 deploy_gateway_openclaw.yml → role roles/vhosts/gateway_openclaw   OpenClaw(2026.5.28)
     ├─5 deploy_xworkmate_bridge_vhosts.yml   BRIDGE + ACP 集群
     │      ├─ import setup-xworkspace-console.yaml（带 bridge 变量再跑一次）
     │      └─ roles: acp_server_codex / acp_server_opencode / acp_server_gemini /
     │               acp_server_hermes / xworkmate_bridge(:8787 本地，公网 Caddy)
     │               域名默认 xworkmate-bridge.svc.plus → acp-bridge.onwalk.net
     ├─6 setup-vault.yaml          → role roles/vhosts/vault        Vault(1.20.4) :8200
     ├─7 setup-postgres-standalone.yaml → role roles/vhosts/postgres(dep: common)  原生 apt PG17 :5432
     ├─8 setup-litellm.yaml        → role roles/vhosts/litellm      pip 安装 :4000
     ├─9 deploy_QMD.yml            → role roles/vhosts/qmd          bun qmd, MCP :8181
     ├─10 deploy_agent_hermes.yml  → role roles/vhosts/acp_server_hermes   ⚠ Hermes 重复部署（与步骤5重叠）
     └─11 setup-xfce-xrdp.yaml [可选] → role roles/vhosts/xfce_xrdp_minimal
            → 拆分为 xfce_desktop_minimal_runtime + remote_desktop_xrdp_server
```

### 3.1 关键发现

1. **公开面冲突**：步骤 2/5 在 `ai_workspace_security_level != strict` 时为 `workspace.svc.plus` 部署公网 Caddy 站点，导致 Portal 也对外暴露，与“Bridge 唯一公开”冲突。
2. **Hermes 重复部署**：步骤 5（ACP 集群内）与步骤 10（独立）各部署一次，冗余。
3. **版本固定点分散**：OpenClaw、Vault 已有固定变量；NodeJS 有但偏宽松（`22.x`/`24.x`）；Hermes、QMD、LiteLLM 缺少显式版本/源固定。

---

## 4. 关键设计决策

### 4.1 对外公开面：Bridge Only

- **Bridge 是默认唯一公开的服务**：`XWORKMATE_BRIDGE_PUBLIC_ACCESS` 默认 `true`，公网域名由 `XWORKMATE_BRIDGE_DOMAIN` 自定义传入（目标主机 `acp-bridge.onwalk.net`）。如需关闭可显式设 `false`。
- `xworkspace_console_public_access` 默认 `false`（仅 `XWORKSPACE_CONSOLE_PUBLIC_ACCESS=true` 时公开）。
- `GATEWAY_OPENCLAW_PUBLIC_ACCESS` / `VAULT_PUBLIC_ACCESS` 默认 `false`；其余（QMD / Hermes / PG / LiteLLM）维持本地监听（`127.0.0.1`），不部署公网 Caddy 站点。
- 实现方式：**最小改动**——仅调整默认值/开关并对齐 env 名称（§2.1），不删除既有 public_access 能力（保留可手动放开）。

### 4.2 Hermes 去重

- `setup-ai-workspace-all-in-one.yml` 中移除步骤 10 的独立 `deploy_agent_hermes.yml` 导入（步骤 5 的 ACP 集群已含 hermes）。
- 保留 `deploy_agent_hermes.yml` 文件本身，供单独部署场景使用，仅从 all-in-one 聚合链里去重。

### 4.3 运行模式矩阵（docker / k3s / systemd）

引入一个**校验型**变量 `ai_workspace_runtime_modes`（列表），在 all-in-one 顶部加一段 `assert` 守卫，不重写各组件部署逻辑：

| 约束 | 规则 |
|---|---|
| 互斥 | `docker` 与 `k3s` 不可同时出现 |
| 可组合 | `docker + systemd` 允许；`systemd` 可单独 |
| 默认 | `['docker','systemd']`（多数 Agent 服务 systemd，PostgreSQL 走 docker compose） |

组件与模式映射（复用现有能力，不新增重型实现）：

| 组件 | systemd | docker | k3s |
|---|---|---|---|
| Console / API / ttyd / Bridge / ACP / OpenClaw / QMD / LiteLLM | ✅ 默认 | — | — |
| PostgreSQL | 可选 | ✅ **默认 docker compose** | 可选 |
| Vault | `vault_deploy_mode=systemd` | — | `vault_deploy_mode=kubernetes`（k3s） |

守卫伪代码（放入 all-in-one 顶层 play）：

```yaml
- name: Validate runtime mode combination
  hosts: all
  gather_facts: false
  tasks:
    - assert:
        that:
          - not ('docker' in ai_workspace_runtime_modes and 'k3s' in ai_workspace_runtime_modes)
          - ai_workspace_runtime_modes | length > 0
        fail_msg: "docker 与 k3s 互斥；请选择 docker/k3s/systemd 的合法组合。"
```

### 4.4 PostgreSQL 默认 docker compose

- 新增开关 `postgresql_deploy_mode`，默认 `compose`。
- `compose` 模式：在 `roles/vhosts/postgres` 增加一条 compose 部署路径（镜像版本固定，端口/口令复用现有变量），与现有原生 apt 路径并存、互斥择一。
- 不删除原生 apt 路径（设 `postgresql_deploy_mode=native` 可回退）。

### 4.5 QMD / LiteLLM 源仓库与版本固定

- QMD：安装源指向 `https://github.com/ai-workspace-services/qmd.git`，新增 `qmd_source_repo` / `qmd_version` 变量固定。
- LiteLLM：安装源指向 `https://github.com/ai-workspace-services/litellm.git`，新增 `litellm_source_repo` / `litellm_version` 变量固定。

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

## 6. 仓库与提交计划

| 仓库 | 主要改动 | Commit message（建议） | 推送目标 |
|---|---|---|---|
| `playbooks` | 角色拆分、版本固定、Bridge 域名、运行模式守卫、PG compose、QMD/LiteLLM 源、聚合链去重、本规划文档 | `feat: deliver versioned AI Workspace Runtime (role split, run-mode matrix, bridge domain)` | `ai-workspace-infra/playbooks` |
| `xworkspace-console` | `setup-ai-workspace-all-in-one.sh` 统一摘要、pull 源对齐、console 默认不公开 | `feat: unified one-time deploy summary + bridge-only public surface` | `ai-workspace-lab/xworkspace-console` |
| `xworkspace-core-skills` | （按需）技能种子/版本对齐 | `chore: align skills seed for workspace runtime` | `ai-workspace-lab/xworkspace-core-skills` |

> 每个仓库**独立提交**，分别记录 Commit Hash 写入最终交付说明。

---

## 7. 部署与验证

### 7.1 部署命令（在目标主机或对其有网络/SSH 访问的环境执行）

```bash
# 远程 exec：脚本在主机上自 GitHub pull 仓库并运行 ansible 到 localhost
# 采用 §2.1 权威环境变量契约（目标主机示例）
ssh root@acp-bridge.onwalk.net \
  'curl -sfL https://raw.githubusercontent.com/ai-workspace-lab/xworkspace-console/main/scripts/setup-ai-workspace-all-in-one.sh | \
   XWORKMATE_BRIDGE_DOMAIN=acp-bridge.onwalk.net \
   XWORKMATE_BRIDGE_PUBLIC_ACCESS=true \
   AI_WORKSPACE_SECURITY_LEVEL=strict \
   bash -'
```

### 7.2 验证清单

- [ ] 脚本结束输出统一摘要，且 Bridge 显示 `https://acp-bridge.onwalk.net`。
- [ ] `curl -I https://acp-bridge.onwalk.net` 可达；其余服务端口仅 `127.0.0.1` 监听。
- [ ] `systemctl --user is-active` 各服务为 `active`。
- [ ] `opencode/gemini/codex/claude --version` 均可执行。
- [ ] 凭据仅在摘要中出现一次。

---

## 8. 风险与回退

| 风险 | 缓解 / 回退 |
|---|---|
| 沙箱无法直连 GitHub/目标主机 | 本地完成代码+提交；push 与远程部署由有网络的环境执行 |
| PG 切 compose 影响既有数据 | 保留 `postgresql_deploy_mode=native` 回退路径 |
| 角色拆分回归 | `setup-xfce-xrdp.yaml` 组合两角色，行为等价；保留旧角色直至引用切换验证通过 |
| 版本固定导致拉取失败 | 版本变量集中、可单点覆盖（env / `-e`） |

---

## 9. 实现顺序（落地次序）

1. 本规划文档入库（docs/）。
2. 角色拆分 + `setup-xfce-xrdp.yaml` 组合。
3. 版本固定（OpenClaw/Vault/Hermes/QMD/LiteLLM/Node/Playwright/Chrome）。
4. Bridge 域名参数透传（`XWORKMATE_BRIDGE_DOMAIN`，自定义，不改 role 默认）。
5. 运行模式守卫 + PG compose 默认。
6. 聚合链去重（Hermes）+ console 默认不公开。
7. `setup-ai-workspace-all-in-one.sh` 统一摘要。
8. 三仓库分别提交，记录 Commit Hash。
9. 推送 + 远程部署 + 按 §7.2 验证。
10. 并发优化落地（见 §10），最后做 §10.8 等价性回归。

---

## 10. 并发优化设计（深入分析 + 定制策略）

> 目标：在**不丢 tasks、不破坏现有 role 结构、不牺牲稳定性**的前提下，提升单机部署速度。
> 总策略：三相执行——**Phase 1 串行（系统全局/抢锁）→ Phase 2 并发（互不依赖 I/O）→ Phase 3 串行（确定性收口）**。不要把多个 role 直接改并发；只把“耗时、互不依赖、不写同一文件、不抢同一锁”的任务做 `async`，最后 `async_status` 收口。

### 10.1 三相模型（权威定义）

**Phase 1 — 必须串行**（抢锁 / 修改系统全局状态）：
`apt update`、`apt install`、`dpkg` 相关、添加 apt repo / keyring、用户/用户组创建、基础目录创建、基础权限设置、Docker 安装、Caddy 安装、systemd 基础准备、防火墙基础规则、**全局 pip / 全局 npm(-g) 安装**。

**Phase 2 — 可以并发**（互不依赖、不写同一文件、不操作同一锁）：
`docker pull` 多镜像、下载多个二进制、`git clone` 多仓库、`go build`、**不同目录**的 `npm/pnpm install`、**不同目录**的前端 build、拉取插件、拉取静态资源、生成互不冲突的服务配置、初始化各服务独立工作目录、各服务独立 prepare 脚本。

**Phase 3 — 必须串行**（收口确定性）：
渲染最终配置、`systemd daemon-reload`、`enable service`、按依赖顺序 `start/restart`、health check、输出部署结果、清理临时文件。

### 10.2 关键定制结论（针对本 Playbook 的深入分析）

1. **所有 `npm -g` 共享同一 prefix → 必须 Phase 1 串行。**
   `roles/vhosts/nodejs` 设 `npm_config_prefix=/usr/local/lib/npm`；Agent CLI（opencode-ai / @google/gemini-cli / @openai/codex / @anthropic-ai/claude-code）、`yarn`、`openclaw@ver` 全部 `npm -g` 到该 prefix。并发会争用同一 `node_modules`/`.staging` 与 npm cache 锁 → **不可并发**。
2. **LiteLLM 是全局 `pip install` → Phase 1 串行**（非项目内 venv，写系统 site-packages）。修正早期草案中“pip 可 async”的判断。
3. **真正安全的 Phase 2 候选是“外部 I/O 预取”**：git clone、二进制下载、docker pull、独立目录的前端 build。它们不碰 dpkg/npm-prefix/pip 全局锁，且写入各自独立路径。
4. **跨 sub-playbook 的并发收益最大处在 Shell 预取层**：11 个步骤由 ansible 顺序导入，play 间难并发；把可并行的 I/O 上提到 bootstrap 的 Phase 2 fork 池（§10.5）预取，ansible 仅消费已就位产物，是收益/风险比最高的定制。
5. **离线包优先**（呼应 TODO）：已有离线安装包/已导入镜像时，Phase 2 预取应短路跳过，直接复用缓存。

### 10.3 现状任务 → 三相映射

| 步骤 / role | Phase 1（串行） | Phase 2（可并发预取） | Phase 3（串行收口） |
|---|---|---|---|
| 1 nodejs | nodesource keyring/repo、`apt install nodejs`、`npm -g yarn` | — | — |
| 2 console | apt(caddy/xfce4/python3/golang-go/chrome)+chrome repo/key、用户/目录/权限 | `get_url` ttyd 二进制、`git clone` console、dashboard `npm install && build`（独立目录） | 渲染 systemd unit/env/portal-services.json、`daemon-reload`/enable/restart、Caddy 写入+reload |
| 3 ai_agent_runtime | `npm -g` Agent CLI、全局 pip(python deps)、apt(browser/docs/fonts)、Playwright(-g) | `agent_skills` 拉取 core-skills 市场（独立目录） | 校验/health、register 输出 |
| 4 gateway_openclaw | `npm -g openclaw@ver`+插件 | （插件若独立目录拉取可并发） | 配置渲染、systemd、版本 assert、health |
| 5 bridge + ACP | 同步 console；acp_server_* 的全局安装部分 | `xworkmate-go-core` 二进制下载/放置、acp 各自独立工作目录 prepare | 配置渲染、按依赖 `requires acp-*.service` 顺序启动、validation |
| 6 vault | （systemd 基础准备） | `get_url` vault zip 下载、解压放置 | 配置渲染、systemd/init、health |
| 7 postgres | Docker 安装、common 基础 | `docker pull` PG 镜像、初始化独立 data 目录 | compose 渲染、`compose up`、health |
| 8 litellm | apt python3-pip、**全局 pip install litellm** | — | 配置渲染、systemd、health(`:4000/health`) |
| 9 qmd | （bun 运行时安装，全局） | 条件并发：qmd 拉取/`bun install`（隔离于 `~/.bun`，不碰 dpkg） | qmd.env/index.yml 渲染、systemd --user、health(`:8181`) |
| 11 xfce（可选） | apt 桌面包/xrdp/chrome、`npm -g`/Playwright | — | xrdp 服务 enable/start、会话配置 |

> 说明：标“条件并发”的（如 qmd `bun`）仅当确认其只写入服务自身用户目录、且不与同时段其它全局安装争锁时才纳入 Phase 2，否则归 Phase 1。

### 10.4 Ansible 层 async 模式（保留全部属性）

在**单个 play 内**对 Phase 2 任务用 `poll:0` 发起、集中 `async_status` 收口。`register`/`when`/`notify`/`tags`/`become`/`failed_when` 一律保留：

```yaml
- name: Download ttyd binary (async)
  ansible.builtin.get_url: { url: "...", dest: "{{ ttyd_path }}", mode: "0755" }
  async: 1800
  poll: 0
  register: ttyd_job

- name: Clone xworkspace-console (async)
  ansible.builtin.git: { repo: "...", dest: "{{ repo_dir }}", version: main, depth: 1 }
  become_user: "{{ xworkspace_console_user }}"
  async: 1800
  poll: 0
  register: console_clone_job

# …其它独立 Phase 2 任务一并 poll:0 发起…

- name: Collect async Phase-2 jobs
  ansible.builtin.async_status: { jid: "{{ item }}" }
  register: p2
  until: p2.finished
  retries: 120
  delay: 5
  loop:
    - "{{ ttyd_job.ansible_job_id }}"
    - "{{ console_clone_job.ansible_job_id }}"
```

- 收口铁律：任一 Phase 2 产物在**被 Phase 3 消费前**必须 `finished`。
- dpkg/全局 npm/全局 pip **绝不** `async`（§10.2）。

### 10.5 Shell 层动态 fork 并发（≤ CPU 核心数 × 2，预取层）

bootstrap 把可并行的外部 I/O 收敛到一个**负载自适应的有界 fork 池**，在 ansible 前（Phase 2 预取）与摘要阶段使用。硬上限为目标主机在线 CPU 核心数的 2 倍；`AI_WORKSPACE_MAX_PARALLEL_JOBS` 可设更低人工上限，默认 `auto`。每次启动子任务前读取 1 分钟 load average，按 `min(人工上限, 2 × CPU - ceil(load1))` 动态收缩，最低保留 1 路：

```bash
CPU_COUNT="$(getconf _NPROCESSORS_ONLN)"
HARD_LIMIT=$((CPU_COUNT * 2))
LOAD_CEILING="$(awk -v load="$(cut -d' ' -f1 /proc/loadavg)" 'BEGIN { n=int(load); print load > n ? n + 1 : n }')"
DYNAMIC_LIMIT=$((HARD_LIMIT - LOAD_CEILING))
[ "$DYNAMIC_LIMIT" -ge 1 ] || DYNAMIC_LIMIT=1

run_bounded() {
  while [ "$(jobs -rp | wc -l)" -ge "$DYNAMIC_LIMIT" ]; do wait -n; done
  "$@" &
}

# Phase 2 预取：5 仓库 pull + 二进制下载 + 镜像 pull（离线包存在则短路跳过）
for r in playbooks console core-skills qmd litellm; do run_bounded fetch_repo "$r"; done
for b in ttyd vault xworkmate-go-core; do run_bounded fetch_binary "$b"; done
for img in "${PG_IMAGES[@]}"; do run_bounded docker_pull "$img"; done
for p in "${pids[@]}"; do wait "$p" || rc=1; done
[ "$rc" -eq 0 ] || { echo "[phase2] 存在失败子任务"; exit 1; }
```

- 健康探测 fan-out（摘要前）：对 Portal/Bridge/OpenClaw/QMD/Hermes/PG/Vault/LiteLLM 的 `systemctl is-active`+`curl` 使用同一动态上限，统一按固定顺序汇总。
- 每子进程带日志前缀（`[repo:qmd]`/`[bin:vault]`），失败非零退出、不静默。
- 串行保留：`ansible-playbook` 主执行（Phase 1/Phase 3 由其内部保证）、一次性 token/摘要打印。

### 10.6 不允许丢失的内容（硬约束）

逐一保留现有所有 tasks 及属性：`apt/package`、用户/目录/权限、env 文件、systemd unit 渲染、Caddy/Nginx、Docker/compose、服务启动、health check、`debug`、失败处理、`handlers`、`tags`、`become`、`when`、`notify`、`register`。**不得因并发删除/合并/跳过任何已有任务**；仅改变“何时等待”（`poll:0`+`async_status`），不改变“做什么”。

### 10.7 安全的全局提速（与 async 互补，不改 task 语义）

`ansible.cfg`（已存在）可叠加低风险项：

```ini
[defaults]
gathering = smart
fact_caching = jsonfile
fact_caching_connection = /tmp/ansible_facts
[ssh_connection]
pipelining = true
```

并补足 TODO 关注点：APT/部署锁需**安全等待**（重试而非强删锁），保证二次幂等执行成功。`strategy: free` 单机收益有限、改变执行观感，**默认不启用**。

### 10.8 验收（等价性回归）

- [ ] 优化前后 `ansible-playbook --list-tasks` 任务集合一致（无丢失/合并）。
- [ ] 每个 `async` 任务都有对应 `async_status` 收口，无悬挂 job。
- [ ] Phase 1（apt/全局 npm/全局 pip/dpkg）与 Phase 3（daemon-reload/enable/start/health/摘要/清理）仍严格串行。
- [ ] Phase 2 任务互不写同一文件、不抢同一锁；离线包存在时短路跳过。
- [ ] 连续两次执行均成功、`changed=0` 幂等行为不变；Shell fork 池失败子任务非零退出且日志可见。

---

## 附录 A. AI Workspace All-in-One Setup（bootstrap 使用指南）

> 面向最终用户的官方安装指南，已合并入本规划作为单一权威来源。
> 本附录相对上游 README 有两处校准：① `XWORKMATE_BRIDGE_PUBLIC_ACCESS` 默认 **`true`**（Bridge 为默认唯一公开服务）；② `acp-bridge.onwalk.net` 为 **host-specific 自定义参数**，经 `XWORKMATE_BRIDGE_DOMAIN` 传入。

这是从 `xworkspace-console` 仓库安装 AI Workspace Runtime 的推荐 bootstrap 入口。脚本以该仓库为公开入口，随后通过 AI Workspace playbooks 与各组件仓库准备运行时服务。

### A.1 标准安装

适用于默认安全的本地工作区，仅需一个生成或既有的统一 token：

```bash
curl -sfL https://raw.githubusercontent.com/ai-workspace-lab/xworkspace-console/main/scripts/setup-ai-workspace-all-in-one.sh | bash -
```

### A.2 进阶安装

在 `bash -` 前用环境变量自定义暴露面、安全级别与可选桌面功能：

```bash
curl -sfL https://raw.githubusercontent.com/ai-workspace-lab/xworkspace-console/main/scripts/setup-ai-workspace-all-in-one.sh | \
  AI_WORKSPACE_SECURITY_LEVEL=strict \
  XWORKSPACE_CONSOLE_ENABLE_XRDP=true \
  XWORKSPACE_CONSOLE_PUBLIC_ACCESS=true \
  XWORKMATE_BRIDGE_PUBLIC_ACCESS=true \
  GATEWAY_OPENCLAW_PUBLIC_ACCESS=false \
  VAULT_PUBLIC_ACCESS=false \
  LITELLM_API_CADDY_STRICT_WHITELIST=true \
  TOKEN="your-unified-auth-token" \
  bash -
```

### A.3 推荐参数

| 变量 | 默认 | 推荐用法 |
|---|---|---|
| `TOKEN` | 生成或复用 | 为 Bridge、Portal、LiteLLM、OpenClaw、Vault 设置一个统一认证 token |
| `AI_WORKSPACE_SECURITY_LEVEL` | `standard` | 公网/半公网主机使用 `strict` |
| `XWORKMATE_BRIDGE_PUBLIC_ACCESS` | `true` | Bridge 为默认唯一公开服务；需关闭对外访问时显式设 `false` |
| `XWORKMATE_BRIDGE_DOMAIN` | host-specific（自定义） | Bridge 公网域名，例如 `acp-bridge.onwalk.net` |
| `XWORKSPACE_CONSOLE_PUBLIC_ACCESS` | `false` | 仅当 Portal 必须公开时开启；本地优先更安全 |
| `GATEWAY_OPENCLAW_PUBLIC_ACCESS` | `false` | 除非 OpenClaw 必须直接暴露，保持 false |
| `VAULT_PUBLIC_ACCESS` | `false` | 常规部署保持 false |
| `LITELLM_API_CADDY_STRICT_WHITELIST` | `false` | strict 部署且 LiteLLM 经 Caddy 暴露时开启 |
| `XWORKSPACE_CONSOLE_ENABLE_XRDP` | `false` | 仅当需要远程桌面访问时开启 |

### A.4 目标主机示例（当前 ACP Bridge 主机）

```bash
curl -sfL https://raw.githubusercontent.com/ai-workspace-lab/xworkspace-console/main/scripts/setup-ai-workspace-all-in-one.sh | \
  XWORKMATE_BRIDGE_DOMAIN=acp-bridge.onwalk.net \
  XWORKMATE_BRIDGE_PUBLIC_ACCESS=true \
  AI_WORKSPACE_SECURITY_LEVEL=strict \
  bash -
```

### A.5 预期最终输出

部署成功后，脚本**一次性**打印部署域名与 token，随后报告以下服务状态：

- AI Workspace 域名与 token
- OpenClaw
- QMD
- PostgreSQL
- Vault
- Workspace Portal / Console
- LiteLLM
- Agent CLI：opencode、gemini、codex、claude

> Token 输出务必私密保存，不得拷入前端源码或提交到 Git。

### A.6 本地 macOS 校验

在 macOS 上脚本默认进入本地校验模式，在 `http://127.0.0.1:17000` 启动 Portal。若因端口占用导致校验失败，先停止已有本地服务或在干净会话中重试。
