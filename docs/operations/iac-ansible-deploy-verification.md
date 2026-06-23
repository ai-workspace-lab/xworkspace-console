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

部署侧加固(长途控制连接稳定性): `ANSIBLE_SSH_ARGS` 加 `ServerAliveInterval/ControlPersist`, `ANSIBLE_SSH_RETRIES`。

## 5. 待办(remaining)

- **console.service 伺服方式**: 预编译 runtime 只发 `dashboard/dist`(无 package.json),
  而服务跑 `npm run preview` → ENOENT 崩溃重启。需改为**静态伺服 dist**(候选: api 二进制自带伺服 / caddy file_server / 静态服务器),属 app 设计决策,未擅改。
- **deploy 流水线**: `deploy-ai-workspace-iac.yaml` 的 deploy job 由"runner 跑 all-in-one"改为"用 inventory 在主机上跑 curl|bash 引导"(契合本地执行模型 + 离线加速)。

## 6. 离线/在线回退确认

- 默认 `AI_WORKSPACE_OFFLINE_MODE=auto` + `AUTO_DOWNLOAD=true` → GitHub Releases 取分片包(`download_offline_split` 重组)。
- `AI_WORKSPACE_OFFLINE_PACKAGE_BASE_URL` 空 → 跳过 rsync 镜像。
- 离线获取失败 → 回退在线: `install_prerequisites` 按系统选 apt/yum/`brew`(macOS), 再 git clone + 在线拉 runtime tar。
