[🇺🇸 English](README.md) | [🇨🇳 中文](README.zh.md)

# XWorkspace Console

XWorkspace Console 是 AI Workspace Lab 的本地 AI 工作区控制平面。它将 React 仪表板、Go 状态 API、systemd 用户服务以及 XFCE 桌面（LinuxVPS 可选）模板整合到一个多标签页界面中，用于服务管理、运行时管理、终端访问以及工作区导航。

## 预览 (Preview)

![XWorkspace Console homepage preview](./assets/readme/homepage.png)

### 图片 / 视频

图片和视频工作流可以作为自定义标签页自然地集成在控制台 shell 中。这使得制品审查、服务切换和运行时操作都集中在一个地方，而不是分散在不同的应用程序中。

## 关于 (About)

- 工作区 UI 的单一入口点：`http://127.0.0.1:17000`
- 以标签页优先的控制台，涵盖工作区、服务、运行时和嵌入式工具
- 旨在协调本地 AI 服务、网关访问和桌面引导流程
- 后端由 `dashboard/`、`api/`、`config/`、`scripts/` 和 `docs/` 支持

## 快速开始 (Start TLDR)

> **注意：** 目前支持 **macOS**、**Debian** 和 **Ubuntu**。其他系统未经测试。

### 安装 (Installation)

1. 启动一体化安装程序：

```bash
curl -sfL https://raw.githubusercontent.com/ai-workspace-lab/xworkspace-console/main/scripts/setup-ai-workspace-all-in-one.sh | bash -
```

2. 自动注册模型（通过 API 密钥）：

在运行安装程序之前导出密钥，会自动在网关中注册模型（例如 DeepSeek、NVIDIA、OLLAMA/GLM）：
```bash
export DEEPSEEK_API_KEY="sk-..."
export NVIDIA_API_KEY="nvapi-..."
export OLLAMA_API_KEY="your-key-here"

curl -sfL https://raw.githubusercontent.com/ai-workspace-lab/xworkspace-console/main/scripts/setup-ai-workspace-all-in-one.sh | bash -
```

3. 离线安装 (Offline installation)：

通过指定文件路径使用预先下载的部署包：
```bash
export AI_WORKSPACE_OFFLINE_PACKAGE="/path/to/offline-package.tar.gz"
curl -sfL https://raw.githubusercontent.com/ai-workspace-lab/xworkspace-console/main/scripts/setup-ai-workspace-all-in-one.sh | bash -
```

### 卸载 (Uninstallation)

```bash
# 标准卸载（保留配置和状态）
curl -sfL https://raw.githubusercontent.com/ai-workspace-lab/xworkspace-console/main/scripts/setup-ai-workspace-all-in-one.sh | bash -s -- uninstall

# 彻底清理（删除所有数据、密钥和配置）
curl -sfL https://raw.githubusercontent.com/ai-workspace-lab/xworkspace-console/main/scripts/setup-ai-workspace-all-in-one.sh | bash -s -- uninstall --purge
```

### 使用 (Usage)

1. 通过浏览器打开控制台：

```text
http://127.0.0.1:17000
```

2. 或启动本地桌面控制台应用程序：

```bash
./scripts/setup-xworkspace-desktop.sh
```

## 下载 (Download)

- 最新源码：[GitHub repository](https://github.com/ai-workspace-lab/xworkspace-console)
- 发布版本：[GitHub Releases](https://github.com/ai-workspace-lab/xworkspace-console/releases)
- 引导脚本：`scripts/setup-ai-workspace-all-in-one.sh`
- 离线安装文档：[`docs/zh/OFFLINE_AI_WORKSPACE_INSTALLER.md`](docs/zh/OFFLINE_AI_WORKSPACE_INSTALLER.md)

## 文档 / 链接 (Docs / Links)

- [`docs/zh/FEATURES.md`](docs/zh/FEATURES.md)
- [`docs/zh/VERSION_MATRIX.md`](docs/zh/VERSION_MATRIX.md)
- [`docs/zh/REPOSITORY_OVERVIEW.md`](docs/zh/REPOSITORY_OVERVIEW.md)
- [`docs/zh/SETUP_AI_WORKSPACE_ALL_IN_ONE.md`](docs/zh/SETUP_AI_WORKSPACE_ALL_IN_ONE.md)
- [`docs/zh/OFFLINE_AI_WORKSPACE_INSTALLER.md`](docs/zh/OFFLINE_AI_WORKSPACE_INSTALLER.md)
- [`docs/zh/operations/service-port-plan.md`](docs/zh/operations/service-port-plan.md)
- [`docs/zh/designs/2026-06-07-ai-workspace-desktop-design.md`](docs/zh/designs/2026-06-07-ai-workspace-desktop-design.md)
