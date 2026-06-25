# Local MCP Debug Pack

This pack is tuned for local debugging with a small tool surface.

## Included

- `github-mcp-server`
- `terraform-mcp-server`
- `mcp-ssh-manager`
- `ansible.mcp` as an Ansible collection dependency, not a standalone MCP daemon

## One-step setup

```bash
cd /Users/shenlan/workspaces/ai-workspace-lab/xworkspace-console
./scripts/setup-local-mcp-debug.sh
```

The script writes:

- `/Users/shenlan/workspaces/ai-workspace-lab/xworkspace-console/config/mcp/local-mcp-config.json`
- `/Users/shenlan/workspaces/ai-workspace-lab/xworkspace-console/config/mcp/local-mcp.env`
- `/Users/shenlan/workspaces/ai-workspace-lab/xworkspace-console/config/mcp/bin/*.sh`

## Recommended defaults

- GitHub MCP stays on the minimal default toolset
- Terraform MCP stays on `registry`
- SSH Manager runs through `npx` to avoid a global install
- The GitHub token stays local in `local-mcp.env`

## Required env vars

- `GITHUB_PERSONAL_ACCESS_TOKEN`
- `TFC_TOKEN` only if you need Terraform Cloud / Enterprise access
