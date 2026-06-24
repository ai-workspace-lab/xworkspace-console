# IaC ↔ Ansible 动态 inventory 联动部署 —— 验证与问题修复记录

日期: 2026-06-24 · 目标机: Vultr `vc2-4c-8gb` × 2(debian13 trixie / ubuntu26.04, nrt)

## 1. 架构与数据流

```
config/resources/ai-workspace-hosts.yaml        (IaC 声明, 唯一人工入口)
  → scripts/generate.py render (Python+Jinja2, 无 for_each)
  → terraform apply  → 2 台 VPS + 公网IP
  → scripts/generate.py inventory  → cmdb.json + inventory.ini
  → playbooks/inventory/terraform_cmdb.py (Ansible 动态 inventory, 只读 cmdb.json)
  → 部署
```

- IaC 模块: `ai-workspace-infra/iac_modules/terraform-hcl-standard/vultr-vps`
- Ansible: `ai-workspace-infra/playbooks`(all-in-one + roles/vhosts/ai-workspace 等)

## 2. 验证结果(已通过)

| 环节 | 结果 |
|------|------|
| IaC 起机(terraform) | 2 台创建成功, plan 与 state 零漂移 |
| 动态 inventory 联动 | `terraform_cmdb.py` 读 cmdb.json, `ansible -m ping` 两台 pong |
| 离线包联动 | install.svc.plus → 302 引导脚本; Release `offline-ai-workspace-14` 含 debian-13-amd64 / ubuntu-26.04-amd64 包(分片); **on-host 安装实测使用了离线包**(日志见 `/var/tmp/ai-workspace-offline/extracted/...`) |
| on-host 部署 | curl\|bash 在主机本地执行, openclaw / ttyd / caddy 起来 |

## 3. 关键架构结论

**all-in-one playbook 设计为"在目标主机本地执行"**(curl|bash → `ansible-playbook -c local`,此时 localhost = 主机)。
从**远程 controller** 跑 `ansible-playbook -i <inventory>` 时,`roles/agent_skills` 大量 `delegate_to: localhost`
并读写 `/root/.agents/skills`、`{{playbook_dir|dirname}}/xworkspace-core-skills/skills` 等 **controller 本地路径**,
会与"controller≠主机"错位(在 mac 上写 `/root` 只读 → 失败)。

> 推论: IaC↔Ansible 联动的正确形态是 **IaC 负责"起机 + 出 inventory",实际部署用 inventory 在每台主机上跑
> 官方 curl|bash 引导**(本地模型, 支持离线加速),而非从 runner 远程跑 all-in-one。
> `xworkspace-console/.github/workflows/deploy-ai-workspace-iac.yaml` 的 deploy job 据此应改为 on-host 引导(见下"待办")。

## 4. 发现的问题与修复

均在 `ai-workspace-infra/playbooks`:

| # | 问题 | 现象 | 修复 |
|---|------|------|------|
| 1 | Python 3.13 + apt + pipelining | apt 任务 `UNREACHABLE` + maxsplit DeprecationWarning | 部署侧 `ANSIBLE_PIPELINING=False` + `PYTHONWARNINGS=ignore`(deploy 流水线已内置) |
| 2 | `xworkspace_console_user` 写死 ubuntu | root 连接时 home=/root 但 user=ubuntu, enable 服务 link `/root` 报 "src does not exist" | `setup-xworkspace-console.yaml`: user 跟随 `ansible_env.USER` |
| 3 | xfce4 大装包拖断 SSH 会话 | "Install runtime packages" UNREACHABLE(包其实装完) | 该 apt 任务加 `async/poll` |
| 4 | ai_agent_runtime apt 抢 dpkg 锁 | texlive/pandoc `Could not get lock` | `roles/ai_agent_runtime/tasks/{main,docs,fonts,browser}.yml` 加 `lock_timeout` |
| 5 | console API 二进制路径错 | `api/xworkspace-api` 不存在 → `203/EXEC` 崩溃重启 | manifest `apiBinary: bin/xworkspace-api`,`setup-xworkspace-console.yaml` 的 `api_dir` 改 `bin/` |
| 6 | console 伺服方式错 | 预编译只发 `dashboard/dist`(无 package.json),`npm run preview` ENOENT(254)崩溃重启 | console 是 `127.0.0.1:17000` 上的**本地静态后端**(dashboard 为无路由单页),Linux `console.service` 与 macOS `console.plist` 统一用 `python3 -m http.server --directory dist`;**不**起第二个 caddy(避免与系统 caddy 抢 :80） |
| 7 | caddy 安装未受开关控制 | console play 无条件 `apt install caddy` | apt 列表里 caddy 由 `caddy_enabled` 门控(VPS 默认 true;关→不装;macOS 无 apt 本就不装) |
| 8 | `module_defaults.apt.lock_timeout`(模板值)经 `ansible.builtin.package` 间接派发到 apt 时**不渲染** | 字面 `{{ ai_workspace_apt_lock_timeout … }}` 当 int 失败 → bootstrap 在 bridge/litellm 之前中止 | Debian 上 `xworkmate_bridge`/`litellm`/`common(fail2ban)` 预装任务改用 `ansible.builtin.apt`(非 Debian 留 `package`,yum/dnf 不继承该默认) |
| 9 | `acp_server_opencode` ACP 端点校验超时 | 服务(重)启后 ~1s 即探测,adapter 已 accept TCP 但未应答;`uri` 默认 30s + `retries/until` 在连接超时上未真正循环,一次即败 | 改为 **curl 重试循环**(每次 5s、最多 ~30 次);adapter 就绪后 `acp.capabilities` ~4ms 回 200 |
| 10 | litellm × Python 3.14(仅 Ubuntu 26.04) | pinned litellm fork 要求 `<3.14`,Ubuntu 26.04 系统 py=3.14 且 apt 无 3.13/3.12 → `pip install` 报 "requires a different Python" | 系统解释器 ≥3.14 时用 **`uv` 装独立 Python 3.13** 重建 venv;Debian 13(3.13)不受影响 |
| 11 | `inventory_hostname` 硬编码短名/127.0.0.1 | 主机标识/hostname/caddy 站点名错位 | `generate.py` 以 `service_domains` 首个 **FQDN** 为 CMDB/inventory 键;`.sh` on-host 的 `-i` 用 FQDN;bridge 角色据此设 `/etc/hostname` 与 caddy 站点名 |

部署侧加固(长途控制连接稳定性): `ANSIBLE_SSH_ARGS` 加 `ServerAliveInterval/ControlPersist`, `ANSIBLE_SSH_RETRIES`。

非空传递检查(默认要求非空,缺失即 fail-fast):`generate.py` 校验每台 `ip`/`instance_id` 非空;流水线各 job `Validate required secrets` 校验必需 Vault 输出;bridge 角色断言 `xworkmate_bridge_domain` 为合法 FQDN(caddy 暴露时)。

## 4b. 公网暴露 / caddy 架构

- **caddy 是统一反代前端**(:80/:443),每个**对外**服务一份 `/etc/caddy/conf.d/*.caddy`(`reverse_proxy` 到其本地端口）。
- **Linux VPS(有公网 IP)**:默认仅 `XWORKMATE_BRIDGE_PUBLIC_ACCESS` 开(经 `-e` 传入)→ bridge 进 conf.d 对外;console(17000）等 `*_PUBLIC_ACCESS` 默认 false → **本地only、无 conf.d**。`caddy_enabled` 默认 true → 装 caddy。
- **macOS 本机**:无需暴露任何公网服务、全内网、`caddy_enabled=false` → **不装 caddy**;console 同样 python 本地伺服。
- 注意 `:80` 由 **apt caddy 包自带的默认 `/etc/caddy/Caddyfile`(`:80 {}`)** 占用;早期把 console 也做成第二个 caddy 会因 auto-HTTPS 预留 :80 而冲突——故 console 改为 python 静态后端、由系统 caddy 反代(本地only 时则不反代）。

## 5. 验证结果

**已确认(全新主机,on-host 引导):**

| 平台 | hostname | console | api | 17000 |
|------|----------|---------|-----|-------|
| debian13(caddy_enabled=true） | — | active(python3） | active | 200 `<title>XWorkspace Dashboard</title>` |
| ubuntu26.04 | `xworkmate-bridge-ubuntu-26.svc.plus`(FQDN ✓) | active(python3） | active | 200 |
| macOS 本机(python3 伺服 dist） | — | — | — | 200 `<title>XWorkspace Dashboard</title>` |

- console(python 伺服）+ api(bin 路径）在两台全新主机直接 active、17000=200(此前 console 崩溃重启）。
- **FQDN hostname** 在 ubuntu 实测生效;agent_skills 重构、lock_timeout(bridge/fail2ban）修复均已越过。

**litellm / qmd:** 三处 package→apt(#8）修复让引导得以推进到 litellm/qmd 相位;`acp_server_opencode` 校验(#9）与 litellm×Py3.14(#10,uv 装 3.13）修复已入库。最近一次两台完整重跑仍以 `rc≠0` 收尾(失败点抓取因工具侧分类器中断未能即时定位）——litellm/qmd 全部 active 的最终确认,留待一次干净重跑/对最新失败点的定位。

- deploy 流水线: `deploy-ai-workspace-iac.yaml` 的 deploy job 已改为"ssh 到主机本地跑 curl|bash 引导"(契合本地执行模型 + 离线加速),provision job 保留为批量起机模式;密钥经 Vault OIDC 取。

## 6. 离线/在线回退确认

- 默认 `AI_WORKSPACE_OFFLINE_MODE=auto` + `AUTO_DOWNLOAD=true` → GitHub Releases 取分片包(`download_offline_split` 重组)。
- `AI_WORKSPACE_OFFLINE_PACKAGE_BASE_URL` 空 → 跳过 rsync 镜像。
- 离线获取失败 → 回退在线: `install_prerequisites` 按系统选 apt/yum/`brew`(macOS), 再 git clone + 在线拉 runtime tar。
