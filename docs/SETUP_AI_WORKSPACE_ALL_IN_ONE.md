# AI Workspace All-in-One Setup

This is the recommended bootstrap entry for installing AI Workspace Runtime from the `xworkspace-console` repository.

The bootstrap script uses this repository as the public entrypoint, then prepares the runtime services through the AI Workspace playbooks and component repositories.

## 1. Standard Install

Use this when you want the default secure local workspace and only need a generated or existing unified token.

```bash
curl -sfL https://raw.githubusercontent.com/ai-workspace-lab/xworkspace-console/main/scripts/setup-ai-workspace-all-in-one.sh | bash -
```

## 2. Advanced Install

Use environment variables before `bash -` to customize exposure, security, and optional desktop features.

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

## 3. Recommended Parameters

| Variable | Default | Recommended Use |
| --- | --- | --- |
| `TOKEN` | generated or reused | Sets one unified auth token for Bridge, Portal, LiteLLM, OpenClaw, and Vault. |
| `AI_WORKSPACE_SECURITY_LEVEL` | standard | Use `strict` for public or semi-public hosts. |
| `XWORKMATE_BRIDGE_PUBLIC_ACCESS` | false | Enable only when the Bridge domain should be reachable from the Internet. |
| `XWORKSPACE_CONSOLE_PUBLIC_ACCESS` | false | Enable only when the Portal must be public. Local-only is safer. |
| `GATEWAY_OPENCLAW_PUBLIC_ACCESS` | false | Keep false unless OpenClaw must be exposed directly. |
| `VAULT_PUBLIC_ACCESS` | false | Keep false for normal deployments. |
| `LITELLM_API_CADDY_STRICT_WHITELIST` | false | Enable with strict deployments when LiteLLM is exposed through Caddy. |
| `XWORKSPACE_CONSOLE_ENABLE_XRDP` | false | Enable only when remote desktop access is required. |
| `XWORKMATE_BRIDGE_DOMAIN` | host-specific | Set the public Bridge domain, for example `acp-bridge.onwalk.net`. |

## 4. Target Host Example

For the current ACP Bridge host:

```bash
curl -sfL https://raw.githubusercontent.com/ai-workspace-lab/xworkspace-console/main/scripts/setup-ai-workspace-all-in-one.sh | \
  XWORKMATE_BRIDGE_DOMAIN=acp-bridge.onwalk.net \
  XWORKMATE_BRIDGE_PUBLIC_ACCESS=true \
  AI_WORKSPACE_SECURITY_LEVEL=strict \
  bash -
```

## 5. Expected Final Output

After a successful deployment, the script prints the deployed domain and token once, then reports service status for:

- AI Workspace domain and token
- OpenClaw
- QMD
- PostgreSQL
- Vault
- Workspace Portal / Console
- LiteLLM
- Agent CLI: `opencode`, `gemini`, `codex`, `claude`

Keep the token output private. It should not be copied into frontend source code or committed to Git.

## 6. Local macOS Validation

On macOS, the script defaults to local validation mode and starts the Portal at:

```text
http://127.0.0.1:17000
```

If validation fails because a port is already in use, stop the existing local service or run in a clean session before retrying.
