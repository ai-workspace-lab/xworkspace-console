# Vault + GitHub Actions 配置（xworkspace-console）

`xworkspace-console` 的 GitHub Actions 经 HashiCorp Vault (https://vault.svc.plus)
OIDC 登录、从**共享 CICD KV** 读取密钥。只记录流程、路径、字段名与原则，
**不含任何敏感值**。延续既有统一模式（见 `vault-github-actions-2026-06-06.md`
与 `vault-github-actions-ssh-deploy-runbook.md`）。

## 1. 全局前提（已存在）

- `jwt` auth mount：Type `jwt`、Path `jwt/`、Accessor 如 `auth_jwt_6fd8b418`
  - `oidc_discovery_url = https://token.actions.githubusercontent.com`
  - `bound_issuer       = https://token.actions.githubusercontent.com`
- 共享机密 KV（KV v2）：UI `secrets/kv/kv/CICD`，API 读路径 `kv/data/CICD`

## 2. role + policy

role/policy 命名 `github-actions-xworkspace-console`，读**共享** `kv/data/CICD`。

```bash
# 2.1 policy：允许读共享 CICD KV 路径
vault policy write github-actions-xworkspace-console - <<'EOF'
path "kv/data/CICD" {
  capabilities = ["read"]
}
path "kv/metadata/CICD" {
  capabilities = ["read", "list"]
}
# LLM provider keys 在 openclaw 路径
path "kv/data/openclaw" {
  capabilities = ["read"]
}
path "kv/metadata/openclaw" {
  capabilities = ["read", "list"]
}
EOF

# 2.2 role：仅绑定本仓库的 GitHub OIDC 身份
vault write auth/jwt/role/github-actions-xworkspace-console \
  role_type="jwt" \
  user_claim="repository" \
  bound_audiences="vault" \
  bound_claims_type="glob" \
  bound_claims='{"repository":"ai-workspace-lab/xworkspace-console","sub":"repo:ai-workspace-lab/xworkspace-console:*"}' \
  token_policies="github-actions-xworkspace-console" \
  token_ttl="20m" token_max_ttl="30m"
```

> 权限模型一致：`repository = ai-workspace-lab/xworkspace-console`、
> `sub = repo:ai-workspace-lab/xworkspace-console:*`、`bound_audiences=["vault"]`。
> 共享 KV 仅授予 read。如需仅限分支，把 `sub` 收窄为
> `repo:ai-workspace-lab/xworkspace-console:ref:refs/heads/main`。

## 3. KV 字段（复用既有共享键，跨两条路径）

| Vault 路径 | 键 | 映射到输出 | 用途 |
| --- | --- | --- | --- |
| `kv/data/CICD` | `VULTR_API_KEY` | `VULTR_API_KEY` | provision：`TF_VAR_vultr_api_key` |
| `kv/data/CICD` | `CODEX_GITHUB_PERSONAL_ACCESS_TOKEN` | `INFRA_REPO_TOKEN` | checkout 私有 `ai-workspace-infra` |
| `kv/data/CICD` | `CLOUDFLARE_DNS_API_TOKEN` | `CLOUDFLARE_DNS_API_TOKEN` | dns：Cloudflare DNS 编辑 |
| `kv/data/CICD` | `SSH_PRIVATE_DEPLOY_KEY_B64` | `ANSIBLE_SSH_KEY_B64` | 连主机 SSH 私钥（**优先**，单行 base64） |
| `kv/data/CICD` | `SSH_PRIVATE_DEPLOY_KEY` | `ANSIBLE_SSH_KEY` | 同上原始多行（回退） |
| `kv/data/openclaw` | `DEEPSEEK_API_KEY` / `NVIDIA_API_KEY` / `OLLAMA_API_KEY` | 同名 | deploy：注入主机的 LLM provider keys |
| `kv/data/CICD` | `TF_STATE_ENDPOINT/BUCKET/ACCESS_KEY/SECRET_KEY/REGION` | 同名 | 可选远端 TF state（不配则本地 state） |

> 所有键均已存在（LLM key 在 `kv/openclaw`，其余共享键在 `kv/CICD`）。
> vault-action 一个步骤可跨多路径读，每行自带路径。

> 主机登录用 `SSH_PRIVATE_DEPLOY_KEY`，其公钥 `SSH_PUBLIC_DEPLOY_KEY` 须写入
> `ai-workspace-infra` 的 `vultr-vps/config/resources/ai-workspace-hosts.yaml`
> 的 `ssh_keys[].public`，否则 runner 连不上新建主机。

## 4. workflow 接入（已落地）

`.github/workflows/deploy-ai-workspace-iac.yaml`：

1. `permissions.id-token: write`（+ `contents: read`）
2. 每 job 用 `hashicorp/vault-action@v2`：`method: jwt`、`role:
   github-actions-xworkspace-console`、`jwtGithubAudience: vault`，从
   `kv/data/CICD` 读所需键（用 `KV键 | 输出名` 映射；可选键配 `ignoreNotFound`）
3. 步骤用 `steps.vault.outputs.<输出名>`，不再用 GitHub Actions Secrets
4. SSH 落盘优先解码 `ANSIBLE_SSH_KEY_B64`(=`SSH_PRIVATE_DEPLOY_KEY_B64`)、回退原始，
   写 `~/.ssh/id_deploy` 并 `ssh-keygen -y -f` 自检
5. 远端 TF state 开关由 `steps.vault.outputs.TF_STATE_BUCKET` 是否非空决定

## 5. 验收

1. 触发 `Deploy AI Workspace (IaC + Ansible + Cloudflare)`。
2. 每个 job 的 `Load Vault secrets (OIDC)` 成功（读到共享 CICD KV）。
3. provision：`Terraform apply` 成功、产出 `cmdb.json` 矩阵。
4. deploy：`Configure SSH`（B64 优先）+ `Run on-host bootstrap` 成功。
5. dns：`Reconcile Cloudflare DNS` 成功。

## 6. 故障处理

- `vault-action` 报 `valid path and key`：`secrets` 每行 `;` 分隔、路径含 `data/`。
- role 不匹配 / `permission denied`：核对 OIDC `repository/sub` 与 role `bound_claims`，及 policy 是否含 `kv/data/CICD`。
- `Load key ... error in libcrypto`：确认优先解码了 `SSH_PRIVATE_DEPLOY_KEY_B64`。
- `Permission denied (publickey)`：确认 `SSH_PUBLIC_DEPLOY_KEY` 已进 hosts.yaml 并与私钥配对。
