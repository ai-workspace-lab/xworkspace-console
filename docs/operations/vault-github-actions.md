# Vault + GitHub Actions 配置（xworkspace-console）

本文档记录 `xworkspace-console` 仓库的 GitHub Actions 经 HashiCorp Vault
(https://vault.svc.plus) OIDC 登录、按仓库隔离读取 KV 密钥的配置。
只记录流程、路径、字段名与配置原则，**不包含任何敏感值**。

延续既有统一模式（见 ai-workspace 体系的 `vault-github-actions-2026-06-06.md`
与 `vault-github-actions-ssh-deploy-runbook.md`），新增仓库只需补：一条 policy、
一条 role、对应 `kv/data/github-actions/<repo>` 路径、workflow 中的 vault-action 步骤。

## 1. 全局前提（已存在，无需重建）

- `jwt` auth mount（UI: Access → Authentication Methods）
  - Type `jwt`，Path `jwt/`，Accessor 如 `auth_jwt_6fd8b418`
  - `oidc_discovery_url = https://token.actions.githubusercontent.com`
  - `bound_issuer       = https://token.actions.githubusercontent.com`
  - Default/Max Lease TTL：1 month 1 day（沿用现状）

## 2. 本仓库专属 policy + role

统一命名：role/policy = `github-actions-xworkspace-console`，KV 读路径
`kv/data/github-actions/xworkspace-console`。

```bash
# 2.1 policy：仅允许读本仓库 KV 路径
vault policy write github-actions-xworkspace-console - <<'EOF'
path "kv/data/github-actions/xworkspace-console" {
  capabilities = ["read"]
}
path "kv/metadata/github-actions/xworkspace-console" {
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
  token_ttl="20m" \
  token_max_ttl="30m"
```

> 权限模型与其它仓库一致：`repository = ai-workspace-lab/xworkspace-console`、
> `sub = repo:ai-workspace-lab/xworkspace-console:*`、`bound_audiences=["vault"]`，
> policy 仅读自己的 KV。如需仅限某分支可把 `sub` 收窄为
> `repo:ai-workspace-lab/xworkspace-console:ref:refs/heads/main`。

## 3. KV 字段（`kv/data/github-actions/xworkspace-console`）

deploy-ai-workspace-iac.yaml 各 job 按需读取：

| 字段 | 用途 | 必填 |
| --- | --- | --- |
| `VULTR_API_KEY` | provision：`TF_VAR_vultr_api_key` | 是 |
| `INFRA_REPO_TOKEN` | checkout 私有 `ai-workspace-infra` 的 PAT | 私有仓库时是 |
| `ANSIBLE_SSH_KEY` | 连主机的 SSH 私钥（原始多行） | 二选一 |
| `ANSIBLE_SSH_KEY_B64` | 同上的 base64 单行（**优先**，避免多行私钥 libcrypto 报错） | 二选一 |
| `CLOUDFLARE_API_TOKEN` | dns：Cloudflare DNS 编辑 token | 同步 DNS 时是 |
| `DEEPSEEK_API_KEY` / `NVIDIA_API_KEY` / `OLLAMA_API_KEY` | deploy：注入主机的 LLM provider keys | 是 |
| `TF_STATE_ENDPOINT` / `TF_STATE_BUCKET` / `TF_STATE_ACCESS_KEY` / `TF_STATE_SECRET_KEY` / `TF_STATE_REGION` | provision：远端 S3 兼容 TF state（不配则用本地 state） | 否 |

```bash
# 写入示例（敏感值请勿入库/勿贴日志）；SSH key 同时存原始与 B64：
vault kv put kv/github-actions/xworkspace-console \
  VULTR_API_KEY=... \
  INFRA_REPO_TOKEN=... \
  CLOUDFLARE_API_TOKEN=... \
  DEEPSEEK_API_KEY=... NVIDIA_API_KEY=... OLLAMA_API_KEY=... \
  ANSIBLE_SSH_KEY=@/path/to/id_deploy \
  ANSIBLE_SSH_KEY_B64="$(base64 -w0 < /path/to/id_deploy)"
```

> SSH 私钥须与 `vultr-vps` 资源声明 `config/resources/ai-workspace-hosts.yaml`
> 的 `ssh_keys[].public` 配对。

## 4. workflow 接入方式（已落地）

`.github/workflows/deploy-ai-workspace-iac.yaml`：

1. `permissions.id-token: write`（+ `contents: read`）
2. 每个 job 用 `hashicorp/vault-action@v2`：`method: jwt`、`role:
   github-actions-xworkspace-console`、`jwtGithubAudience: vault`、
   从 `kv/data/github-actions/xworkspace-console` 读所需字段（可选字段配
   `ignoreNotFound: true`）
3. 各步骤用 `steps.vault.outputs.<KEY>`，不再使用 GitHub Actions Secrets
4. SSH 落盘优先解码 `ANSIBLE_SSH_KEY_B64`、回退 `ANSIBLE_SSH_KEY`，并
   `ssh-keygen -y -f` 自检
5. 远端 TF state 的开关由 `steps.vault.outputs.TF_STATE_BUCKET` 是否非空决定

## 5. 验收步骤

1. 触发 `Deploy AI Workspace (IaC + Ansible + Cloudflare)`（workflow_dispatch）。
2. 确认每个 job 的 `Load Vault secrets (OIDC)` 成功（读到本仓库 KV）。
3. provision：`Terraform apply` 成功、产出 `cmdb.json` 矩阵。
4. deploy：`Configure SSH` 成功（B64 优先）、`Run on-host bootstrap` 成功。
5. dns：`Reconcile Cloudflare DNS` 成功。

## 6. 故障处理

- `vault-action` 报 `valid path and key`：检查 `secrets` 每行用 `;` 分隔、KV 路径含 `data/`。
- `permission denied` / role 不匹配：核对 OIDC `sub/repository` 与 role 的 `bound_claims`。
- `Load key ... error in libcrypto`：确认 workflow 读取并优先解码了 `ANSIBLE_SSH_KEY_B64`。
- `Permission denied (publickey)`：本地用同一私钥先 SSH 验证，再更新 Vault；确认与 hosts.yaml 公钥配对。
