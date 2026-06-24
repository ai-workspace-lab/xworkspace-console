# IaC ↔ Ansible 动态 inventory 联动工作流

端到端梳理：**YAML 资源声明 → Python+Jinja2 渲染显式 HCL → Terraform 起机 →
CMDB/inventory 生成 → Ansible 部署**。配套 Vault(OIDC)取密钥、Cloudflare DNS 同步。

- IaC 侧：`ai-workspace-infra/iac_modules/terraform-hcl-standard/vultr-vps`
- Ansible 侧：`ai-workspace-infra/playbooks`
- 编排/流水线：`xworkspace-console/.github/workflows/deploy-ai-workspace-iac.yaml`
- 相关文档：[vault-github-actions.md](vault-github-actions.md) · [iac-ansible-deploy-verification.md](iac-ansible-deploy-verification.md) · IaC 渲染约束见 `iac_modules/terraform-hcl-standard/AGENTS.md` 与 `skills/terraform-yaml-render-pattern/SKILL.md`

## 1. 数据流

```
config/resources/ai-workspace-hosts.yaml      # 唯一人工入口（global / ssh_keys / hosts）
        │
        │  generate.py render   （YAML → 显式 HCL，无 for_each/count/dynamic）
        ▼
  workdir/{provider.tf, variables.tf, cloud-init.yaml, generated_hosts.tf,
           terraform.auto.tfvars.json}
        │
        │  terraform apply       （创建 VPS + 公网 IP）
        ▼
  terraform output cmdb_runtime  （只输出运行时才确定的事实：ip / instance_id / os_id）
        │
        │  generate.py inventory （运行时事实 + YAML 静态字段 合并）
        ▼
  workdir/{cmdb.json, inventory.ini}           # 数据契约（gitignore，不入库）
        │                       │
        │ terraform_cmdb.py     │ inventory.ini
        ▼ (动态 inventory)       ▼ (静态 inventory)
              Ansible 部署（两种执行模型，见 §4）
```

> 渲染产物（`generated_hosts.tf` / `terraform.auto.tfvars.json` / `cmdb.json` /
> `inventory.ini` 等）均 `.gitignore`，IaC 变更后重跑 `generate.py inventory` 再生成。

## 2. 数据契约 cmdb.json

`generate.py inventory` 产出，贯穿三个流水线 job，也是动态 inventory 的唯一来源
（不直接耦合 tfstate）。**以 `service_domains` 首个 FQDN 为键**（动态取自 YAML；
无 service_domains 时回退 `name`）——即 `inventory_hostname` 是真实 FQDN，绝不硬编码短名/127.0.0.1。

```jsonc
{
  "xworkmate-bridge-debian-13.svc.plus": {     // key = inventory_hostname (FQDN)
    "name": "ai-debian13",                     // 资源声明里的短名（terraform 模块名）
    "fqdn": "xworkmate-bridge-debian-13.svc.plus",
    "ip": "x.x.x.x",                           // 运行时事实（terraform output）
    "instance_id": "...", "os_id": 2625,
    "os_name": "Debian 13 x64 (trixie)", "plan": "vc2-4c-8gb", "region": "nrt",
    "ansible_user": "root",
    "groups": ["ai_workspace", "debian"],
    "host_vars": { "service_domains": "...", "role": "primary", ... }
  }
}
```

## 3. generate.py 两个子命令

| 子命令 | 输入 | 输出 | 职责 |
| --- | --- | --- | --- |
| `render` | `config/resources/*.yaml` | `generated_hosts.tf` + `terraform.auto.tfvars.json` + 拷入共享 `.tf` | YAML→显式 HCL（Jinja2 展开命名唯一块）；global 段进 tfvars |
| `inventory` | `terraform output cmdb_runtime` + YAML | `cmdb.json` + `inventory.ini` | 合并「运行时事实 + 静态字段」；以 FQDN 为键 |

参数化：`--resources` / `--workdir`（共享一份脚本，不在每个 env 各放一份）。

## 4. 两种执行模型（关键）

**all-in-one playbook 设计为「在目标主机本地执行」**（见 [iac-ansible-deploy-verification.md](iac-ansible-deploy-verification.md) §3）。

| 模型 | 调用 | localhost | 适用 |
| --- | --- | --- | --- |
| **本地 / pull** | `curl\|bash` → `ansible-playbook -i <FQDN>, -c local` | = 目标主机本身 | self-host、流水线 deploy job（ssh 到主机后本地跑） |
| **远程 controller** | `ansible-playbook -i <inventory> root@host`（经 SSH） | = controller(runner/mac) | 批量管控；但 `roles/agent_skills` 历史上 `delegate_to: localhost` 会错位 |

- `roles/agent_skills` 已重构为**全程在目标主机执行**（`git clone` 取源、`copy` 合并、无 `delegate_to: localhost`），两种模型行为一致。
- 流水线 deploy job 采用**本地/pull**：runner 仅 ssh 到主机执行官方引导，主机内部 `-c local`（自动离线包加速），规避 controller≠主机 的错位，且与用户 self-host 同一路径。
- on-host 的 `inventory_hostname` 由 `.sh` 取 `XWORKMATE_BRIDGE_DOMAIN`（流水线注入 = CMDB service_domains）或主机 FQDN，绝不硬编码 127.0.0.1。

## 5. 流水线（deploy-ai-workspace-iac.yaml）

| job | 作用 | 开关 |
| --- | --- | --- |
| `provision` | terraform 起机 + 渲染 cmdb.json + 动态生成部署矩阵 | `terraform_action=apply` |
| `deploy`（matrix/主机） | 按 cmdb.json 取 IP，ssh 到主机本地跑 `curl\|bash` 引导 | `run_deploy` |
| `dns` | 依据 inventory 的 service_domains/IP 同步 Cloudflare A 记录 | `run_dns` |

- **密钥**：不用 GitHub Secrets，经 **Vault OIDC(JWT)** 从 `kv/data/CICD`（VULTR/SSH/Cloudflare/INFRA token）与 `kv/data/openclaw`（LLM keys）读取；详见 [vault-github-actions.md](vault-github-actions.md)。
- **公网暴露**：Linux VPS 默认仅 `XWORKMATE_BRIDGE_PUBLIC_ACCESS=true`（bridge 进 `/etc/caddy/conf.d/`）；console(17000) 等本地only。macOS 全内网、`caddy_enabled=false` 不装 caddy。

## 6. 非空传递检查与 fail-fast（默认要求非空）

| 边界 | 检查 | 失败行为 |
| --- | --- | --- |
| terraform → cmdb.json | `generate.py inventory` 校验每台 `ip`/`instance_id` 非空 | `sys.exit` + 列出缺失主机 |
| Vault → 流水线 job | 每 job `Validate required secrets` 步骤校验必需 `steps.vault.outputs.*` 非空 | `::error::` 命名缺失键/路径 + `exit 1` |
| 域名 → hostname/caddy | bridge 角色断言 `xworkmate_bridge_domain` 为非空 FQDN（caddy 暴露时） | `assert` fail_msg 指引设置 env/service_domains |
| bridge 二进制 / auth token | bridge 角色既有 `assert` | fail_msg |

## 7. 一次部署（操作）

```bash
# 流水线：GitHub Actions → "Deploy AI Workspace (IaC + Ansible + Cloudflare)" → Run workflow
#   inputs: terraform_action=apply, run_deploy=true, run_dns=true

# 本地手动（IaC 起机 + 出 inventory）：
cd iac_modules/terraform-hcl-standard/vultr-vps
export TF_VAR_vultr_api_key=...            # 机密走环境变量，禁止入 YAML/tfvars
python3 scripts/generate.py render
terraform -chdir=envs/ai-workspace init && terraform -chdir=envs/ai-workspace apply
python3 scripts/generate.py inventory      # 缺 ip 会 fail-fast
# 部署：在每台主机上跑 curl|bash 引导（本地模型），或用 inventory.ini 驱动
```

## 8. 已应用的关键修复（端到端可用前提）

- **console 伺服**：预编译 runtime 只发 `dashboard/dist`，改用 `python3 -m http.server` 本地伺服（Linux/macOS 统一，不起第二个 caddy）。
- **api 路径**：manifest `apiBinary: bin/xworkspace-api`，修正 `api_dir` 至 `bin/`。
- **agent_skills**：重构为主机本地 `git clone` + `copy`，去 `delegate_to: localhost`。
- **apt lock_timeout**：`module_defaults.apt.lock_timeout`(模板值)经 `ansible.builtin.package` 间接派发到 apt 时不渲染 → Debian 上相关预装任务改用 `ansible.builtin.apt`（bridge/litellm/fail2ban）。
- **py3.13**：`ANSIBLE_PIPELINING=False` + `PYTHONWARNINGS=ignore`。
- **inventory_hostname = service_domains FQDN**（动态、非硬编码）。
