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

---

## 修复维度总结

| 维度 | 涉及用例 |
|------|---------|
| 组件获取方式替换 (brew vs binary) | TC-001 |
| 权限收缩 (become: false) | TC-002, TC-006, TC-007, TC-008, TC-009 |
| 用户组适配 (staff vs ubuntu) | TC-003, TC-010 |
| 目录路径降级 ($HOME vs /home/ubuntu, /opt) | TC-004, TC-006, TC-009, TC-010, TC-012 |
| 包管理器绕过 (skip apt on Darwin) | TC-008, TC-010 |
| 模板变量解耦 (remove nvm/nodejs_version) | TC-005 |
| 路径空格兼容 (argv vs string) | TC-011 |
