[🇺🇸 English](../../README.md) | [🇨🇳 中文](../../README.zh.md)

# 代码库概览

本文档收集了对于维护者和集成者来说有用的代码库细节，同时保持主页 README 专注于使用入口。

## 核心结构

- `config/xworkspace-desktop.yaml`
  - 桌面端口、浏览器选择和服务命名的单一事实来源
- `scripts/`
  - 设置、重置、安装和浏览器启动辅助脚本
- `config/xfce4/`
  - XFCE 面板、窗口管理器、会话和快捷方式模板
- `config/autostart/`
  - 控制台的 XDG 自动启动入口
- `config/systemd/user/`
  - 用于控制台、OpenClaw、Bridge、LiteLLM 和 Vault 的 systemd 用户服务
- `api/`
  - 暴露 `/health`、`/services` 和 `/metrics/simple` 的 Go API
- `dashboard/`
  - React + Vite + TypeScript 仪表板

## 主要服务名称

此代码库在命名上将 `xworkspace-console` 统一标准化为主要的本地控制平面 UI 服务。

早期重叠的名称（如 `xworkspace-dashboard` 和 `xworkspace-portal`）被视为历史概念，而不是该代码库中独立的主要服务。

## 端点规划

规范的本地控制台端点是：

- `http://127.0.0.1:17000`

端口分配：

- `17000`: XWorkspace 控制台 React 仪表板
- `8788`: XWorkspace Go 状态 API
- `8787`: XWorkmate Bridge 控制平面
- `18789`: OpenClaw 网关
- `4000`: LiteLLM UI/API
- `8200`: Vault
- `7681`: ttyd 嵌入式终端
- `7000`: 已弃用的旧版门户，不要在新的控制台部署中使用

查看 [`docs/operations/service-port-plan.md`](./operations/service-port-plan.md) 以了解实机检查和迁移顺序。

## 备注

- XFCE 仍然是桌面基础层。
- 仪表板是基于 React + Vite + TypeScript 构建的。
- 状态 API 是用 Go 编写的。
- 服务管理通过 systemd 用户单元进行。
- 主题和 Shell 定制通过 XFCE 配置、兼容 GTK/XDG 的模板以及 Shell 脚本来处理。
