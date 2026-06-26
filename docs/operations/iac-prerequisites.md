# IaC 流水线前置条件

`Deploy AI Workspace (IaC + Ansible + Cloudflare)` 首次运行前必须完成以下六项。
已完成项打 ✅；未完成会导致对应 job 失败并报 `缺少必需机密` 错误。

---

## TLDR

```
Vault role/policy  ✅ 已创建（2026-06-24）
kv/CICD 必填键     ⬜ VULTR_API_KEY / SSH 私钥 / CLOUDFLARE_DNS_API_TOKEN
kv/openclaw 必填键 ⬜ DEEPSEEK_API_KEY / NVIDIA_API_KEY / OLLAMA_API_KEY
kv/CICD 可选键     ⬜ TF_STATE_* （不填走本地 state，生产建议填）
infra repo token   ⬜ CODEX_GITHUB_PERSONAL_ACCESS_TOKEN （仓库为 public 时可跳过）
SSH 公钥注入 infra ⬜ hosts.yaml ssh_keys[].public
```

---

## 1. Vault JWT auth（全局，已存在）

`vault.svc.plus` 上已有 JWT auth mount，`oidc_discovery_url` 指向
`https://token.actions.githubusercontent.com`。这是所有仓库共用的基础设施，
**不需要重建**，仅在 mount 丢失时才需要重新配置。

---

## 2. Vault role + policy（✅ 已创建 2026-06-24）

```bash
export VAULT_ADDR=https://vault.svc.plus

# 校验是否存在
vault policy read github-actions-xworkspace-console
vault read auth/jwt/role/github-actions-xworkspace-console \
  | grep -E 'bound_claims|token_policies|token_ttl'
```

若缺失，创建命令见 [vault-github-actions.md §2](vault-github-actions.md)。

---

## 3. Vault KV 必填键

用 `vault kv patch`（**不要用 put**，put 会清空路径下其他已有键）：

```bash
export VAULT_ADDR=https://vault.svc.plus

# ── kv/CICD ──────────────────────────────────────────────────
vault kv patch kv/CICD \
  VULTR_API_KEY="<Vultr 账号 API key>" \
  SSH_PRIVATE_DEPLOY_KEY_B64="<私钥 base64 单行>" \
  CLOUDFLARE_DNS_API_TOKEN="<CF Zone DNS Edit token>"

# SSH 私钥 base64 编码方式（macOS）：
#   base64 -i ~/.ssh/id_deploy | tr -d '\n'
# SSH 私钥 base64 编码方式（Linux）：
#   base64 -w 0 ~/.ssh/id_deploy

# ── kv/openclaw ──────────────────────────────────────────────
vault kv patch kv/openclaw \
  DEEPSEEK_API_KEY="<DeepSeek API key>" \
  NVIDIA_API_KEY="<NVIDIA API key>" \
  OLLAMA_API_KEY="<Ollama API key>"
```

### 键说明

| Vault 路径 | 键 | job | 必填 |
|---|---|---|---|
| `kv/CICD` | `VULTR_API_KEY` | provision | ✅ |
| `kv/CICD` | `SSH_PRIVATE_DEPLOY_KEY_B64` | deploy | ✅（与下方二选一） |
| `kv/CICD` | `SSH_PRIVATE_DEPLOY_KEY` | deploy | ✅（原始多行，回退） |
| `kv/CICD` | `CLOUDFLARE_DNS_API_TOKEN` | dns | ✅ |
| `kv/openclaw` | `DEEPSEEK_API_KEY` | deploy | ✅ |
| `kv/openclaw` | `NVIDIA_API_KEY` | deploy | ✅ |
| `kv/openclaw` | `OLLAMA_API_KEY` | deploy | ✅ |

---

## 4. Vault KV 可选键（TF 远端 state）

不填则 Terraform 用本地 state（每次运行隔离，适合演示；**生产必须配远端**，
否则 `destroy` 需要与 `apply` 在同一次运行）。

```bash
vault kv patch kv/CICD \
  TF_STATE_ENDPOINT="https://<s3-compatible-endpoint>" \
  TF_STATE_BUCKET="<bucket-name>" \
  TF_STATE_ACCESS_KEY="<access-key>" \
  TF_STATE_SECRET_KEY="<secret-key>" \
  TF_STATE_REGION="<region>"
```

### 推荐后端

**Vultr Object Storage**（与主机同一服务商，最简单）：
- 控制台 → Object Storage → Add → 选地域（如 New Jersey）
- 得到 Hostname（如 `ewr1.vultrobjects.com`）+ Access/Secret Key
- 用 S3 客户端建 bucket（如 `ai-workspace-tfstate`）：
  ```bash
  aws s3 mb s3://ai-workspace-tfstate \
    --endpoint-url https://ewr1.vultrobjects.com \
    --region us-east-1
  ```
- 填入 `TF_STATE_ENDPOINT=https://ewr1.vultrobjects.com`，`TF_STATE_REGION=us-east-1`

**AWS S3**
- 如果后端是 AWS S3 标准 bucket，`TF_STATE_ENDPOINT` 通常直接填 S3 API endpoint，例如 `https://s3.us-east-1.amazonaws.com`
- `TF_STATE_REGION` 需要与 bucket 所在区域一致；对 `ai-workspace-tfstate` 这类 us-east-1 bucket，填 `us-east-1`

**Cloudflare R2**（已在用 CF，无出口流量费）：
- 控制台 → R2 → 建 bucket → Manage API Tokens → 建读写 token
- `TF_STATE_ENDPOINT=https://<account_id>.r2.cloudflarestorage.com`
- `TF_STATE_REGION=auto`（R2 必须是 `auto`，不可填其他值）

---

## 5. ai-workspace-infra repo token（可选）

仓库为 public 时 `actions/checkout` 无需 token，可跳过。

若为 private：

```bash
vault kv patch kv/CICD \
  CODEX_GITHUB_PERSONAL_ACCESS_TOKEN="<PAT，需 repo read 权限>"
```

---

## 6. SSH 公钥注入 hosts.yaml

`SSH_PRIVATE_DEPLOY_KEY` 对应的**公钥**必须预先写入
`ai-workspace-infra` 仓库的主机配置，否则 Terraform 创建主机后
runner 无法 SSH 登录（`Permission denied (publickey)`）。

文件路径：`vultr-vps/config/resources/ai-workspace-hosts.yaml`

```yaml
ssh_keys:
  - name: deploy-key
    public: "ssh-ed25519 AAAA... your-deploy-key"
```

获取公钥：
```bash
# 从私钥派生
ssh-keygen -y -f ~/.ssh/id_deploy

# 或从 B64 私钥派生
echo "<B64>" | base64 -d | ssh-keygen -y -f /dev/stdin
```

---

## 故障速查

| 错误 | 原因 | 解决 |
|---|---|---|
| `role "github-actions-xworkspace-console" could not be found` | Vault role 未创建 | 见 §2 / vault-github-actions.md |
| `No match data was found` for `TF_STATE_*` | vault-action v2 对键级缺失报错 | 填入 §4 的可选键，或暂时容忍本地 state |
| `缺少必需机密 VULTR_API_KEY` | kv/CICD 键未写入 | 见 §3 |
| `Load key ... error in libcrypto` | SSH 私钥格式错误 | 优先用 `SSH_PRIVATE_DEPLOY_KEY_B64` 单行 base64 |
| `Permission denied (publickey)` | 公钥未注入 hosts.yaml | 见 §6 |
