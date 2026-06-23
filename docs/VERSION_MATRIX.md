# 版本兼容性与组件矩阵 (Version Matrix)

此文档列出了 AI Workspace Lab 控制台 (XWorkspace Console) 及其关联组件的推荐运行环境与组件版本。

## 操作系统 (Operating Systems)
- **macOS**: 26 / 27
- **Linux (Debian)**: 11 / 12 / 13
- **Linux (Ubuntu LTS)**: 22.04 / 24.04 / 26.04

## 运行时环境 (Runtimes)
- **Python**: 3.14
- **NodeJS**: 22

## 核心服务与组件 (Services & Components)
- **OpenClaw**: 2026.6.1
- **QMD**: 2.1 (定制版)
- **Hermes**: 1.15
- **PostgreSQL**: 16
  - **核心扩展 (Extensions)**: `pgvector`, `uuid-ossp`, `pgcrypto`
- **Vault**: v1.21.4
- **LiteLLM**: v1.89

## Agent 命令行工具 (Code Agent CLI)
- `gemini` (Antigravity)
- `code`
- `opencode`
- `claude`
