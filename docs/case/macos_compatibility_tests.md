# macOS 兼容性部署测试用例

本文档记录了在 macOS (Darwin) 环境下进行 `setup-ai-workspace-all-in-one.sh` 全自动部署时遇到的跨平台兼容性问题及修复方案。

## 核心背景

原脚本和 Ansible Playbooks 是为 Debian/Ubuntu Linux 设计的，强依赖 `root` 权限、`apt` 包管理器、系统目录（`/usr/local/sbin`、`/etc/systemd`）及默认用户路径（`/home/ubuntu`）。在 macOS 无提权模式下部署，触发了大量权限与路径异常。

---

## TC-MAC-001: TTYD 二进制与路径异常

| 项目 | 内容 |
|------|------|
| **触发文件** | `setup-ai-workspace-all-in-one.sh` |
| **触发报错** | 脚本尝试下载 ttyd 二进制写入 `/usr/local/bin/ttyd`，无权限且架构不匹配 |
| **修复方案** | Darwin 下拦截二进制下载，改用 `brew install ttyd`；使用 `command -v ttyd` 动态解析路径 |

## TC-MAC-002: 全局提权 (Sudo) 阻塞

| 项目 | 内容 |
|------|------|
| **触发文件** | `setup-ai-workspace-all-in-one.sh` → Ansible Playbook |
| **触发报错** | `sudo: a password is required` |
| **修复方案** | Darwin 下注入 `--extra-vars "ansible_become=false"` 取消自动提权 |

## TC-MAC-003: 默认用户组分配失败

| 项目 | 内容 |
|------|------|
| **触发文件** | `setup-xworkspace-console.yaml` |
| **触发报错** | `chown` 找不到 `ubuntu` 组 |
| **修复方案** | 条件渲染：`"{{ 'staff' if ansible_os_family == 'Darwin' else 'ubuntu' }}"` |

## TC-MAC-004: 写死绝对路径 (Hardcoded Paths)

| 项目 | 内容 |
|------|------|
| **触发文件** | `setup-xworkspace-console.yaml` 头部变量区 |
| **触发报错** | `cd /home/ubuntu/xworkspace-console/dashboard: No such file or directory` |
| **修复方案** | 将 `xworkspace_console_home` 重构为 `{{ ansible_env.HOME }}`, 所有派生目录链式求值 |

## TC-MAC-005: 模板引擎渲染异常 (Undefined Variable)

| 项目 | 内容 |
|------|------|
| **触发文件** | `console.plist.j2` |
| **触发报错** | `AnsibleUndefinedVariable: 'nodejs_version' is undefined` |
| **修复方案** | 移除 NVM 环境初始化和 `nodejs_version` 依赖，直接追加 `/opt/homebrew/bin` 至 PATH |

## TC-MAC-006: NPM 全局助手脚本安装拒绝

| 项目 | 内容 |
|------|------|
| **触发文件** | `roles/ai_agent_runtime/tasks/nodejs.yml` |
| **触发报错** | `chown failed: [Errno 1] Operation not permitted: '/usr/local/sbin/...'` |
| **修复方案** | macOS 下安装路径降级至 `~/.local/bin`，前置创建目录，关闭 `become` |

## TC-MAC-007: Playwright 硬编码关联调用失败

| 项目 | 内容 |
|------|------|
| **触发文件** | `roles/ai_agent_runtime/tasks/nodejs.yml` |
| **触发报错** | `[Errno 13] Permission denied: '/usr/local/sbin/ai-workspace-manage-npm-global-package'` |
| **修复方案** | 所有 `cmd` 中统一使用条件路径语句 |

## TC-MAC-008: Apt 浏览器安装崩溃

| 项目 | 内容 |
|------|------|
| **触发文件** | `roles/ai_agent_runtime/tasks/browser.yml` |
| **触发报错** | `[Errno 2] No such file or directory: b'update'`（macOS 无 apt） |
| **修复方案** | 增加 `when: ansible_os_family != 'Darwin'`；补充 macOS Chrome 探测路径；环境变量脚本路径改为用户目录 |

## TC-MAC-009: Playwright 环境变量挂载目录缺失

| 项目 | 内容 |
|------|------|
| **触发文件** | `roles/ai_agent_runtime/tasks/browser.yml` |
| **触发报错** | `Destination directory ~/.local/state/ai-workspace/env does not exist` |
| **修复方案** | 前置创建 env 目录；变量增加 `default(ansible_env.HOME)` 容错 |

## TC-MAC-010: Agent Skills 角色硬编码路径与用户

| 项目 | 内容 |
|------|------|
| **触发文件** | `roles/agent_skills/defaults/main.yml`、`roles/agent_skills/tasks/main.yml` |
| **触发报错** | `[Errno 45] Operation not supported: b'/home/ubuntu'` |
| **修复方案** | defaults 全部改为 `ansible_env.USER/HOME`；apt rsync 安装增加 Darwin 跳过 |

## TC-MAC-011: Chromium 版本检查路径含空格

| 项目 | 内容 |
|------|------|
| **触发文件** | `roles/ai_agent_runtime/tasks/verify.yml` |
| **触发报错** | `No such file or directory: b'/Applications/Google'`（路径含空格被拆分） |
| **修复方案** | `ansible.builtin.command` 改用 `argv` 列表形式传参，避免空格截断 |

## TC-MAC-012: XWorkMate Bridge 基础目录写入系统路径被拒

| 项目 | 内容 |
|------|------|
| **触发文件** | `setup-ai-workspace-all-in-one.sh` → `roles/vhosts/xworkmate_bridge`（变量 `xworkmate_bridge_base_dir`） |
| **触发报错** | `TASK [roles/vhosts/xworkmate_bridge/ : Ensure xworkmate-bridge base directory exists]` → `There was an issue creating /opt/cloud-neutral as requested: [Errno 13] Permission denied: b'/opt/cloud-neutral'` |
| **根因** | `xworkmate_bridge_base_dir` 默认硬编码为 `/opt/cloud-neutral/xworkmate-bridge`，macOS 以 `ansible_become=false` 运行，无权写入 `/opt`；且 `/opt` 并非 macOS 标准目录。该 base dir 同时被 `config.yaml`、launchd plist 的 `WorkingDirectory` 引用 |
| **目录策略** | Linux 保持 `/opt/cloud-neutral/xworkmate-bridge`；macOS 改用 Apple 标准的用户级应用数据目录 `~/Library/Application Support/cloud-neutral/xworkmate-bridge` |
| **修复方案** | 双层：①`setup-ai-workspace-all-in-one.sh` 的 Darwin 分支注入 `-e xworkmate_bridge_base_dir="$HOME/Library/Application Support/cloud-neutral/xworkmate-bridge"`（`curl \| bash` 拉取的是本仓库脚本，playbooks 来自独立仓库，故脚本侧 `-e` 是该路径下唯一可生效的修复点）；②role `defaults/main.yml` 将默认值改为按 `ansible_os_family` 的三元表达式，使离线/本地 playbook 路径亦正确 |
| **生效前提** | `curl \| bash` 从 GitHub `main` 拉取脚本，修复必须先 push 到 `ai-workspace-lab/xworkspace-console` 的 `main`；否则远端仍是旧脚本（extra-vars 优先级最高，若 `-e` 已执行则绝不会回落到 `/opt`，由此可判定执行的是未修复的远端脚本） |

## TC-MAC-013: Vault standalone 目录写入系统路径被拒

| 项目 | 内容 |
|------|------|
| **触发文件** | `roles/vhosts/vault/tasks/main.yml`、`roles/vhosts/vault/vars/main.yml`、`roles/vhosts/vault/tasks/macos.yml` |
| **触发报错** | `TASK [roles/vhosts/vault/ : Ensure standalone Vault directories exist]` → `[Errno 13] Permission denied: b'/etc/vault.d'`、`b'/opt/vault'` |
| **根因** | “Ensure standalone Vault directories exist” 任务以 `owner: root` 创建 `/etc/vault.d` 与 `/opt/vault/data`，且**缺失** vault 角色其余 standalone 任务都带的 `ansible_os_family != 'Darwin'` 守卫。macOS 以 `become=false` 运行，既无权写 `/etc`、`/opt`，`owner: root` 的 chown 也无法完成。与 bridge 不同（其目录 owner 为服务用户，可由 `-e` 修复），该任务的 `owner: root` 为硬编码，无法用 extra-vars 覆盖，必须改 role 逻辑 |
| **目录策略** | Linux 保持 `/etc/vault.d`、`/opt/vault/data`；macOS 改用 Apple 标准 `~/Library/Application Support/vault`、`~/Library/Application Support/vault/data`；二进制路径 macOS 取 `/opt/homebrew/bin/vault`（brew 安装位置），免去需 sudo 的 `/usr/local/bin` 软链依赖 |
| **修复方案** | role 位于独立 playbooks 仓库，无法从本仓库直接提交；沿用脚本既有的“克隆后打补丁”机制（参见 `patch_playbook_user_systemd`），在 `setup-ai-workspace-all-in-one.sh` 新增 `patch_playbook_vault_macos()`，仅在 Darwin 下对克隆出的 vault 角色：①给目录创建任务追加 `ansible_os_family != 'Darwin'` 守卫；②把 `vault_config_dir`/`vault_data_dir`/`vault_binary_path` 改为按 OS 的三元表达式；③在 `macos.yml` 前置创建用户属主的数据目录（含 launchd 日志目录 `~/.local/state/xworkspace`）。该补丁对 `curl \| bash` 与本地执行两条路径均生效，幂等，且不改动 Linux 行为 |

## TC-MAC-014: common 角色 Linux 基线（timedatectl 等）在 macOS 失败

| 项目 | 内容 |
|------|------|
| **触发文件** | `roles/vhosts/common/tasks/main.yml` |
| **触发报错** | `TASK [common : Base | set timezone]` → `[Errno 2] No such file or directory: b'timedatectl'`（macOS 无 systemd 的 `timedatectl`） |
| **根因** | `common` 角色的 `Base | *` 系列任务是 Linux 服务器基线：`timedatectl` 设时区、改写 `/etc/hostname`、`/etc/hosts`、设主机名、加固 SSH、配置 fail2ban、调文件句柄上限、放行防火墙端口。全部 `become: true` 且依赖 Linux 专有工具/路径，在 macOS（`become=false`）下会逐条失败，`set timezone` 只是第一个 |
| **修复方案** | 经评估这些基线对 macOS 本机开发部署既不适用也无权限执行，故在 `setup-ai-workspace-all-in-one.sh` 新增 `patch_playbook_common_macos()`（同样走克隆后打补丁），仅在 Darwin 下为整个 `Base | *` 块追加 `ansible_os_family != 'Darwin'` 守卫（共 9 处：7 个任务追加 `when`，2 个已有 `when` 列表追加该条件）。`import_tasks` 的 `when` 会传播到子任务，因此 ssh 加固/fail2ban/limits/firewall 子任务一并跳过。幂等、YAML 合法、Linux 行为不变 |
| **备注** | 用户仅点名 `set timezone`，但其后的 Base 任务会以相同原因连环失败，故一并守卫以避免逐个往返 |

## TC-MAC-015: Vault 管理员初始化脚本在 macOS 缺依赖/缺 PATH

| 项目 | 内容 |
|------|------|
| **触发文件** | `roles/vhosts/vault/tasks/main.yml`（Bootstrap 任务）、`roles/vhosts/vault/files/init_vault_admin.sh`、`roles/vhosts/vault/tasks/macos.yml` |
| **触发报错** | `TASK [vault : Bootstrap Vault admin userpass auth]` 失败（`no_log: true` 隐藏详情）。vault 此时已起（健康检查已过），失败发生在执行 `init_vault_admin.sh` |
| **根因** | 脚本 `require_cmd vault/jq/curl/base64`。macOS 默认**不带 jq**，而安装 jq 的 “Install standalone Vault dependencies”（apt）任务带 `!= 'Darwin'` 守卫被跳过 → jq 缺失；同时 `ansible.builtin.script` 使用最小 PATH，未含 Homebrew 的 `/opt/homebrew/bin`，即使已 `brew install` 的 `vault`/`jq` 也可能找不到 |
| **修复方案** | 扩展 `patch_playbook_vault_macos()`：①在 `macos.yml` 增加 `brew install jq`（`creates: /opt/homebrew/bin/jq`）；②给 Bootstrap 任务追加 `environment: PATH: "/opt/homebrew/bin:/usr/local/bin:{{ ansible_env.PATH }}"`，确保脚本能找到 brew 安装的 vault/jq。脚本本身已自带 macOS 适配（`base64 -D` 探测）。补丁幂等、YAML 合法、Linux 不变 |
| **备注** | 若仍失败，可临时将该任务 `no_log` 关掉以查看 `init_vault_admin.sh` 的真实 stderr 再定位 |

## TC-MAC-016: Vault 管理员初始化非幂等（re-run 报 missing entityID）

| 项目 | 内容 |
|------|------|
| **触发文件** | `roles/vhosts/vault/files/init_vault_admin.sh` |
| **触发报错** | `Error writing data to identity/mfa/method/totp/admin-generate ... Code: 400 ... * missing entityID`，并伴随 `A login request was issued that is subject to MFA validation` |
| **根因** | 脚本通过“以该用户登录”来获取 `entity_id`（`auth/userpass/login/<user>`）。但脚本随后又创建了 userpass 的 login-MFA enforcement。dev 模式 Vault 在多次部署之间持续运行（launchd 常驻），因此**第二次及以后**的部署中该登录被 MFA 拦截，返回的不是完整 token 而是 MFA 待校验响应，`entity_id` 为空 → `admin-generate` 报 `missing entityID`。这是 re-run 幂等性缺陷，非 macOS 特有（Linux 第二次跑同样会中招） |
| **修复方案** | 不再依赖会被 MFA 拦截的登录：改为通过 userpass 的 identity **entity-alias** 解析 `entity_id`——遍历 `identity/entity-alias/id` 找到 name==用户、mount_accessor==userpass accessor 的别名取其 `canonical_id`；首次运行（无别名）则显式创建 entity + entity-alias。移除随之不再需要的 `vault token revoke`。幂等、向后兼容（能识别旧版本登录隐式创建的 entity）。已在真实 playbooks 仓库 `init_vault_admin.sh` 修复；clone 路径由 `patch_playbook_vault_macos()` 同步打补丁 |
| **定位手段** | 该任务 `no_log: true` 隐藏了错误；临时改 `no_log: false` + register + 将 stdout/stderr 写入挂载目录文件，直接读取得到真实报错 |

## TC-MAC-017: PostgreSQL 在 macOS 误用 compose 模式

| 项目 | 内容 |
|------|------|
| **触发文件** | `roles/vhosts/postgres/tasks/compose.yml`、`roles/vhosts/postgres/defaults/main.yml` |
| **触发报错** | `TASK [postgres : Materialize PostgreSQL admin password]` 失败（`no_log: true`）。assert `postgresql_admin_password | length > 0` 为空 |
| **根因** | `postgresql_deploy_mode` 默认 `compose`。compose.yml 走 Docker 路径（检查/安装 apt 版 docker），且 `postgresql_admin_password` 默认经 `lookup('password', '/root/.ai_workspace_postgres_password ...')` 生成——macOS 无权写 `/root`，lookup 失败 → 密码为空 → assert 失败。该角色其实已备 `native`+`macos.yml`（Homebrew postgresql@16）路径，但默认未在 macOS 切换过去 |
| **目录/模式策略** | macOS 部署 `postgresql_deploy_mode=native`（→ `macos.yml`，brew 安装）；Linux 部署保持默认 `compose` |
| **修复方案** | 在 `setup-ai-workspace-all-in-one.sh` 的 Darwin 分支注入 `-e postgresql_deploy_mode=native`，并以 `append_secret_var postgresql_admin_password=$UNIFIED_AUTH_TOKEN` 直接提供密码（extra-vars 优先级最高，彻底绕过 `/root` 的 password lookup）。Linux 分支不变 |

## TC-MAC-018: postgres native 安装误用过期 Intel Homebrew 崩溃

| 项目 | 内容 |
|------|------|
| **触发文件** | `roles/vhosts/postgres/tasks/macos.yml` |
| **触发报错** | `Ensure PostgreSQL 16 is installed via Homebrew` → `/usr/local/Homebrew/.../macos_version.rb: unknown or unsupported macOS version: "27.0" (MacOSVersion::Error)` |
| **根因** | 该任务用 `community.general.homebrew` 模块，模块自行探测 brew 前缀，命中了机器上**过期的 Intel Homebrew**（`/usr/local/Homebrew`），其内置 macOS 版本表不认识 `27.0`，brew 启动即崩溃。而 vault/openclaw 用 `command: brew`（走 PATH 上可用的 brew，如 Apple Silicon 的 `/opt/homebrew`）则正常——这是模块选错 brew，而非 brew 整体不可用 |
| **修复方案** | 与 vault/openclaw 对齐：改用 `ansible.builtin.command: brew install postgresql@16`，并在 `environment.PATH` 前置 `/opt/homebrew/bin:/usr/local/bin`（优先选可用的 brew），加 `HOMEBREW_NO_AUTO_UPDATE=1`；`register`+`changed_when`/`failed_when` 维持幂等。真实仓库 `macos.yml` 已改；clone 路径由 `patch_playbook_postgres_macos()` 同步补丁 |
| **备注** | 若该机仅有一个且过期的 brew（纯 Intel），根因为环境，需 `brew update`/重装 Homebrew；本修复在“存在可用 brew”时即可绕过（vault 步骤已证明存在可用 brew） |

## TC-MAC-019: litellm 同样误用 Homebrew 模块崩溃

| 项目 | 内容 |
|------|------|
| **触发文件** | `roles/vhosts/litellm/tasks/main.yml` |
| **触发报错** | `Install LiteLLM prerequisites (macOS)` → `/usr/local/Homebrew/.../macos_version.rb: unknown or unsupported macOS version: "27.0"` |
| **根因** | 与 TC-MAC-018 同源：`community.general.homebrew` 模块命中过期 Intel Homebrew 崩溃 |
| **修复方案** | 改 `ansible.builtin.command: brew install python@3.13` + `environment.PATH` 前置 `/opt/homebrew/bin:/usr/local/bin` + `HOMEBREW_NO_AUTO_UPDATE=1`。真实仓库已改；clone 路径由 `patch_playbook_litellm_macos()` 同步补丁 |
| **备注** | litellm 后续仍有 macOS 缺口待逐个处理：`/root` 派生的 salt/db 密钥 assert、`/etc/litellm` 配置目录、`become: true` + `become_user` 的 pip/prisma 任务（服务用户在 macOS 未创建）、DB provisioning 等 |

## 当前进展快照（2026-06-22）

当前 macOS 调试入口仍以公开安装命令为准：

```bash
curl -sfL https://install.svc.plus/ai-workspace | bash -
```

截至 2026-06-22，`xworkspace-console` 的 bootstrap 入口、`playbooks` 的 all-in-one role 链路、`ai-workspace-services/litellm` 的 runtime 发布链路已经形成三仓库协同。macOS 本地部署已越过早期路径、权限、Homebrew、Vault、PostgreSQL、OpenClaw、QMD 等阻塞点，当前主要剩余风险集中在 LiteLLM 依赖安装的网络稳定性、离线 runtime release 的产物验证，以及最终连续两次幂等部署。

已推送到 `ai-workspace-infra/playbooks` 的关键提交：

| Commit | 主题 | 对 macOS 部署的影响 |
|---|---|---|
| `09a39e6` | `perf(openclaw): avoid unnecessary doctor repairs` | 将 OpenClaw doctor 与 restart 拆开，避免普通 restart 触发 `doctor --fix --force` |
| `f01e0bb` | `fix(qmd): provision macOS LaunchAgent` | 为 QMD 补用户级 LaunchAgent，支持 macOS 下启动 MCP 服务 |
| `c11f51b` | `fix(openclaw): allow version-matched acpx plugin` | 兼容版本匹配的 `acpx` 插件，避免插件注册表 assert 误杀 |
| `71ebe64` | `fix(litellm): isolate runtime in Python 3.13 venv` | LiteLLM 改为 Python 3.13 venv 隔离，避免 Python 3.13/3.14 混用 |
| `6a2f05f` | `fix(litellm): skip redundant dependency installs` | 增加包探测和安装标记，重复执行时跳过已满足的 LiteLLM 依赖安装 |

已推送到 `ai-workspace-services/litellm` 的关键提交：

| Commit | 主题 | 对 macOS/离线部署的影响 |
|---|---|---|
| `51cde5e32` | `ci: add offline litellm runtime workflow` | 新增 `.github/workflows/offline-package-litellm-runtime.yaml`，产出 `litellm-runtime-<distro>-<version>-<arch>.tar.gz`，供 console 离线包脚本消费 |

当前仍需用一次干净安装验证 `install.svc.plus` 指向的远端脚本是否已经包含最新 bootstrap 逻辑。如果失败点仍显示旧任务或旧路径，应先确认发布入口是否已经同步到 `ai-workspace-lab/xworkspace-console@main` 最新版本。

## TC-MAC-020: OpenClaw doctor 过重导致 handler 慢

| 项目 | 内容 |
|------|------|
| **触发文件** | `roles/vhosts/gateway_openclaw/handlers/main.yml` |
| **触发现象** | `RUNNING HANDLER [roles/vhosts/gateway_openclaw/ : Repair OpenClaw health findings (POSIX)]` 耗时约 5-6 秒；此前 restart 与 doctor 绑定，普通配置变化也可能触发 `openclaw doctor --fix --force --yes` |
| **根因** | handler 将“轻量 restart”和“doctor repair”耦合，且 `--fix --force` 默认做修复路径，适合真实健康问题，不适合每次部署收口都跑 |
| **修复方案** | `playbooks` 中已拆分 doctor 与 restart：日常只做 lightweight restart；只有 package/config/plugin 等实际变化才触发 doctor；优先使用较轻的检查/repair 模式，减少无关变化把 doctor 拉起来 |
| **验证状态** | 已提交 `09a39e6`。仍需在完整 macOS 部署中观察 OpenClaw handler 是否只在真实变更时触发 |

## TC-MAC-021: QMD 缺 macOS LaunchAgent

| 项目 | 内容 |
|------|------|
| **触发文件** | `roles/vhosts/qmd/` |
| **触发现象** | QMD MCP 端口 `http://localhost:8181/mcp` 需要作为 macOS 用户服务运行，但 role 缺少 launchd provisioning |
| **根因** | Linux/systemd 路径已有服务管理，macOS 缺少 `LaunchAgents/plus.svc.xworkspace.qmd.plist` 等用户级服务描述 |
| **修复方案** | 新增 QMD LaunchAgent：`plus.svc.xworkspace.qmd`，以 macOS 用户级服务方式启动 |
| **验证状态** | 已提交 `f01e0bb`。仍需在完整安装后验证 `launchctl` 状态与 `http://localhost:8181/mcp` 可达 |

## TC-MAC-022: OpenClaw Codex 插件兼容性 assert 误杀

| 项目 | 内容 |
|------|------|
| **触发文件** | `roles/vhosts/gateway_openclaw/tasks/main.yml` |
| **触发报错** | `Assert OpenClaw Codex plugin matches gateway version` 失败，提示必须运行 `@openclaw/codex 2026.6.1` 与 `openclaw-multi-session-plugins 2026.6.1`，并且不得保留 stale global `@openclaw/acpx` |
| **根因** | assert 将 `acpx` 一律视为 stale，但当前 OpenClaw 插件注册表可能包含版本匹配的 `acpx`，应检查版本而非只检查存在性 |
| **修复方案** | 调整 assert：允许 version-matched `acpx`，仅拒绝 stale/global 不匹配版本 |
| **验证状态** | 已提交 `c11f51b`。仍需在全量部署中观察插件注册表刷新后 assert 结果 |

## TC-MAC-023: LiteLLM Python 3.13/3.14 混用

| 项目 | 内容 |
|------|------|
| **触发文件** | `roles/vhosts/litellm/defaults/main.yml`、`roles/vhosts/litellm/tasks/main.yml` |
| **触发现象** | macOS 上 Homebrew Python 与系统/其它 Python 版本混用，LiteLLM 依赖可能被装进不一致的解释器或 site-packages，后续 `prisma generate` 与服务启动不稳定 |
| **根因** | 早期安装路径没有强制独立 venv，且 macOS 环境里可能同时存在 Python 3.13、3.14 |
| **修复方案** | LiteLLM runtime 固定使用 Python 3.13 创建隔离 venv：`~/.local/share/litellm/venv`；`pip`、`litellm`、`prisma` 均从该 venv 执行 |
| **验证状态** | 已提交 `71ebe64`。仍需完整部署验证服务启动和 `prisma generate` |

## TC-MAC-024: LiteLLM 依赖安装慢且公网下载易中断

| 项目 | 内容 |
|------|------|
| **触发文件** | `roles/vhosts/litellm/tasks/main.yml`、`roles/vhosts/litellm/defaults/main.yml` |
| **触发报错** | `Ensure LiteLLM and DB dependencies are installed` 最长耗时约 581 秒，随后因 `IncompleteRead` / `curl 18` / GitHub archive 或 PyPI wheel 下载中断失败 |
| **根因** | `litellm[proxy]` 依赖树大，包含 `polars-runtime-32`、`cryptography`、`boto3`、`mcp` 等大量包；直接在线 `pip install` 既慢又依赖网络稳定性。将 `git+https` 改为 GitHub archive 后解决了 git clone EOF，但仍无法避免大 wheel 下载中断 |
| **已修复** | ① 默认安装源由 `git+https` 改为 GitHub archive；② 增加 `PIP_CACHE_DIR` 和更长 timeout；③ 安装前探测已装 `litellm/prisma/psycopg2-binary`，并用 `.install-spec` 标记跳过重复安装；④ 新增 `ai-workspace-services/litellm` 的 offline runtime workflow，预构建目标发行版 wheelhouse |
| **当前状态** | 在线安装路径已缓解但未根除网络风险；真正的长期解法是让 all-in-one 优先消费 `litellm-runtime-<distro>-<version>-<arch>.tar.gz` 中的 wheelhouse |
| **待验证** | 需要触发并确认 `offline-package-litellm-runtime.yaml` 在 GitHub Actions 生成 release，且 `xworkspace-console/scripts/create-ai-workspace-offline-package.sh` 能拉取 `ai-workspace-services/litellm` 的 matching runtime asset |

## TC-MAC-025: LiteLLM runtime release 与 all-in-one 离线包对接

| 项目 | 内容 |
|------|------|
| **触发文件** | `ai-workspace-services/litellm/.github/workflows/offline-package-litellm-runtime.yaml`、`xworkspace-console/scripts/create-ai-workspace-offline-package.sh`、`xworkspace-console/scripts/ai-workspace-offline-install.sh` |
| **契约** | console 离线包脚本会下载 `LITELLM_RUNTIME_RELEASE_REPO=ai-workspace-services/litellm` 下的 `litellm-runtime-${DISTRO_ID}-${DISTRO_VERSION}-${ARCH}.tar.gz`，解包后复制 `packages/pip`、可选 `packages/python`、`metadata/runtime.env` |
| **已完成** | `litellm` 仓库新增 workflow，矩阵覆盖 Debian 11/12/13 与 Ubuntu 22.04/24.04/26.04 的 amd64/arm64；Ubuntu 26.04 额外打包 portable Python 3.13.14；release 中合并 SHA256SUMS |
| **待处理** | 需要检查 GitHub Actions 实际 run 是否成功；需要确认 release tag 命名与 console 侧 `latest-runtime` 解析一致；需要在离线 all-in-one 包里实测 `metadata/litellm-runtime.env` 是否正确注入 `LITELLM_PACKAGE_SPEC` |

## TC-MAC-026: uninstall purge 需要打印删除路径

| 项目 | 内容 |
|------|------|
| **触发命令** | `curl -sfL https://install.svc.plus/ai-workspace \| bash -s -- uninstall purge` |
| **需求** | purge 模式不仅删除本地状态，还要明确打印将删除/已删除的路径，便于用户确认清理范围 |
| **当前状态** | 已识别为待处理项；需要在 `setup-ai-workspace-all-in-one.sh` 的 uninstall/purge 分支中抽出统一 `purge_path` / `purge_matching_paths` helper，删除前输出存在路径，不存在时也输出 skipped/absent |
| **涉及路径** | macOS 至少包括 `~/.ai_workspace_auth_token`、`~/.vault_password`、`~/.openclaw`、`/tmp/xworkspace-core-skills`、`/tmp/xworkmate-bridge`、`/tmp/ai-workspace-deploy`；Linux 还包括 `/opt/ai-workspace`、`/etc/ai-workspace`、用户 systemd unit 等 |

## TC-MAC-027: 非源码正式目录清理

| 项目 | 内容 |
|------|------|
| **触发现象** | 工作区出现类似 `ai-workspace-all-in-one-offline-ubuntu-22.04-amd64/` 的生成目录 |
| **根因** | 离线包构建/解包产物进入了开发工作区，容易被误认为源码目录 |
| **处理原则** | 不属于源码仓库正式目录的生成产物应从工作区清理；离线包输出应放在明确的 `dist/`、release artifact 或临时目录中，不应混入源码根目录 |
| **待处理** | 后续需要补一次仓库级清扫：确认 `xworkspace-console`、`playbooks`、`litellm` 各自 `git status --ignored`，清理未跟踪离线包目录，并按需要补 `.gitignore` |

---

## 修复维度总结

| 维度 | 涉及用例 |
|------|---------|
| 组件获取方式替换 (brew vs binary) | TC-001 |
| 权限收缩 (become: false) | TC-002, TC-006, TC-007, TC-008, TC-009 |
| 用户组适配 (staff vs ubuntu) | TC-003, TC-010 |
| 目录路径降级 ($HOME vs /home/ubuntu, /opt, /etc) | TC-004, TC-006, TC-009, TC-010, TC-012, TC-013 |
| 克隆后补丁注入 (post-clone patch) | TC-013, TC-014 |
| Linux 基线整体跳过 (skip Linux baseline on Darwin) | TC-014 |
| brew 补依赖 + PATH 注入 (jq via brew, Homebrew on PATH) | TC-015 |
| 包管理器绕过 (skip apt on Darwin) | TC-008, TC-010 |
| 模板变量解耦 (remove nvm/nodejs_version) | TC-005 |
| 路径空格兼容 (argv vs string) | TC-011 |
| Homebrew 模块绕过 (command brew + PATH) | TC-018, TC-019 |
| macOS launchd 用户服务 | TC-021 |
| handler 触发条件收敛 | TC-020 |
| Python venv 隔离与 pip 缓存 | TC-023, TC-024 |
| 离线 runtime wheelhouse | TC-025 |
| purge 可观测性 | TC-026 |
