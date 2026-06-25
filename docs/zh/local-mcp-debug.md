# 本机 MCP 调试包

这个调试包面向 `xworkspace-console` 的本地联调场景，目标是尽量少的安装步骤、尽量少的 MCP 工具暴露面。

## 覆盖范围

- `github-mcp-server`
- `terraform-mcp-server`
- `mcp-ssh-manager`
- `ansible.mcp` 作为 Ansible collection 依赖安装，不是独立 MCP 服务

## 一键准备

```bash
cd /Users/shenlan/workspaces/ai-workspace-lab/xworkspace-console
./scripts/setup-local-mcp-debug.sh
```

脚本会生成：

- `/Users/shenlan/workspaces/ai-workspace-lab/xworkspace-console/config/mcp/local-mcp-config.json`
- `/Users/shenlan/workspaces/ai-workspace-lab/xworkspace-console/config/mcp/local-mcp.env`
- `/Users/shenlan/workspaces/ai-workspace-lab/xworkspace-console/config/mcp/bin/*.sh`

## 推荐用法

- GitHub MCP 默认只开 `default` 工具集对应的最小面，再补少量常用工具集
- Terraform MCP 默认只开 `registry`
- SSH Manager 用 `npx` 启动，避免全局安装
- GitHub token 只写入本地 `local-mcp.env`，不会进入聊天内容

## 需要的环境变量

- `GITHUB_PERSONAL_ACCESS_TOKEN`
- `TFC_TOKEN` 仅当你要连 Terraform Cloud / Enterprise 时才需要

## 调试建议

- 先用 GitHub MCP 复现 action / PR / repo 相关问题
- 再按需打开 Terraform MCP 的 `terraform` 工具集
- SSH Manager 用于远程主机调试，不影响前两个 server
