[🇺🇸 English](../../README.md) | [🇨🇳 中文](../../README.zh.md)

# AI Workspace 一站式安装

这是从 `xworkspace-console` 仓库安装 AI Workspace Runtime 的推荐启动程序入口。

启动脚本以本仓库为公开入口点，随后通过 AI Workspace playbooks 和组件仓库准备运行时服务。

## 1. 标准安装

当需要默认安全的本地工作区且仅需要生成或现有的统一 token 时使用此方式。

```bash
curl -sfL https://raw.githubusercontent.com/ai-workspace-lab/xworkspace-console/main/scripts/setup-ai-workspace-all-in-one.sh | bash -
```

## 2. 进阶安装

在 `bash -` 之前使用环境变量来自定义公开访问、安全级别和可选的桌面功能。

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

## 3. 推荐参数

| 变量 | 默认值 | 推荐用法 |
| --- | --- | --- |
| `TOKEN` | 生成或复用 | 为 Bridge、Portal、LiteLLM、OpenClaw 和 Vault 设置统一认证 token。 |
| `AI_WORKSPACE_SECURITY_LEVEL` | standard | 公网或半公网主机使用 `strict`。 |
| `XWORKMATE_BRIDGE_PUBLIC_ACCESS` | false | 仅当 Bridge 域名需要从互联网访问时启用。 |
| `XWORKSPACE_CONSOLE_PUBLIC_ACCESS` | false | 仅当 Portal 必须公开时启用。仅限本地访问更安全。 |
| `GATEWAY_OPENCLAW_PUBLIC_ACCESS` | false | 除非 OpenClaw 必须直接暴露，否则保持为 false。 |
| `VAULT_PUBLIC_ACCESS` | false | 常规部署保持为 false。 |
| `LITELLM_API_CADDY_STRICT_WHITELIST` | false | strict 部署且 LiteLLM 经 Caddy 暴露时启用。 |
| `XWORKSPACE_CONSOLE_ENABLE_XRDP` | false | 仅当需要远程桌面访问时启用。 |
| `XWORKMATE_BRIDGE_DOMAIN` | 特定于主机 | 设置公开的 Bridge 域名，例如 `acp-bridge.onwalk.net`。 |
| `AI_WORKSPACE_OFFLINE_PACKAGE` | 无 | 使用预下载的离线包进行安装（例如 `/path/to/offline.tar.gz`）。 |

## 4. 目标主机示例

对于当前 ACP Bridge 主机：

```bash
curl -sfL https://raw.githubusercontent.com/ai-workspace-lab/xworkspace-console/main/scripts/setup-ai-workspace-all-in-one.sh | \
  XWORKMATE_BRIDGE_DOMAIN=acp-bridge.onwalk.net \
  XWORKMATE_BRIDGE_PUBLIC_ACCESS=true \
  AI_WORKSPACE_SECURITY_LEVEL=strict \
  bash -
```

## 5. 预期最终输出

部署成功后，脚本会一次性打印部署的域名与 token，然后报告以下服务状态：

- AI Workspace 域名与 token
- OpenClaw
- QMD
- PostgreSQL
- Vault
- Workspace Portal / Console
- LiteLLM
- Agent CLI：`opencode`、`gemini`、`codex`、`claude`

请妥善保管 token。它不应该被复制到前端源代码或提交到 Git 中。

## 6. 本地 macOS 验证

在 macOS 上，脚本默认进入本地验证模式并在以下地址启动 Portal：

```text
http://127.0.0.1:17000
```

如果因为端口已被占用导致验证失败，请先停止现有的本地服务或在干净的会话中重试。
