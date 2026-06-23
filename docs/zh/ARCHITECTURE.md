[🇺🇸 English](../../README.md) | [🇨🇳 中文](../../README.zh.md)

# XWorkspace 架构

XWorkspace 是一个构建在标准 Linux、systemd、Chrome / Chromium 以及本地运行时服务之上的 AI 工作区 Shell。

核心理念很简单：

不要向用户暴露传统的 Linux 桌面。
使用 Chrome / Chromium 作为桌面 Shell，并使用本地 AI 工作区门户作为主要入口点。

XWorkspace 并不是要从头构建一个完整的操作系统。它保持了 Linux 基础的稳定和标准，同时用一个原生 AI 工作区替换了面向用户的桌面体验。

⸻

## 1. 设计目标

XWorkspace 围绕以下原则进行设计：

### 1. Chrome / Chromium 作为桌面 Shell
    用户通过 Chrome / Chromium 而不是 XFCE、GNOME 或传统的桌面环境进入工作区。

### 2. 门户优先的用户体验
    主要的工作区 UI 是一个本地的 Web 门户，通常暴露在：http://localhost:17000

3. 最少的传统桌面暴露
    XWorkspace 避免暴露面板、桌面图标、文件管理器桌面或传统的应用程序菜单。
4. 本地优先的运行时服务
    核心服务通过用户级 systemd 服务在本地运行。
5. 面向 AI 智能体的工作流
    工作区针对智能体 (Agent)、终端 (Terminal)、浏览器使用 (Browser Use)、计算机使用 (Computer Use)、模型网关 (Model Gateway)、金库 (Vault)、工作流 (Workflow)、技能 (Skill) 和插件 (Plugin) 场景进行了优化。
6. 可组合的服务架构
    每个运行时能力都是一个独立的服务，可以单独启动、停止、升级或替换。

⸻

## 2. 顶层架构

```i11·
┌──────────────────────────────────────────────┐
│ Layer 1：Chrome / Chromium 桌面 Shell         │
│                                              │
│ - 应用模式 (App mode) / Kiosk 模式            │
│ - 全屏工作区入口                               │
│ - 替换传统的 Linux 桌面入口                     │
│ - 打开 http://localhost:17000                 │
└──────────────────────┬───────────────────────┘
                       ↓
┌──────────────────────────────────────────────┐
│ Layer 2：AI 工作区门户 (AI Workspace Portal)   │
│                                              │
│ - 仪表板 (Dashboard)                          │
│ - 应用启动器 (App launcher)                   │
│ - 运行时状态 (Runtime status)                  │
│ - 智能体主会话 (Agent sessions)                │
│ - 终端 / VSCode / 文件                        │
│ - 模型 / 金库 / 工作流入口                      │
└──────────────────────┬───────────────────────┘
                       ↓
┌──────────────────────────────────────────────┐
│ Layer 3：核心服务 (Core Services)              │
│                                              │
│ - 桥接 (Bridge)                               │
│ - 智能体运行时 / 网关 (Agent Runtime / Gateway)│
│ - LiteLLM 代理                                │
│ - 金库 / 金库代理 (Vault / Vault Proxy)        │
│ - ttyd                                        │
│ - 状态生成器 (Status Generator)                │
│ - 本地 API / SSE / WebSocket                  │
└──────────────────────┬───────────────────────┘
                       ↓
┌──────────────────────────────────────────────┐
│ Layer 4：应用 / 附加服务 (App / Extra Services) │
│                                              │
│ - 智能体 (Agent)                              │
│ - 技能 (Skill)                                │
│ - 工作流 (Workflow)                           │
│ - 插件 (Plugin)                               │
│ - 计算机使用 (Computer Use)                    │
│ - 浏览器使用 (Browser Use)                     │
│ - 代码服务器 (Code Server)                     │
│ - 文件浏览器 (File Browser)                    │
└──────────────────────────────────────────────┘
```

## 3. 运行时流程

Linux 启动
  ↓
用户级 systemd 会话
  ↓
核心服务启动
  ↓
xworkspace-portal.service 启动本地门户
  ↓
xworkspace-shell.service 启动 Chrome / Chromium
  ↓
Chrome / Chromium 打开 http://localhost:17000
  ↓
用户进入 AI 工作区门户
  ↓
门户与桥接、智能体、LiteLLM、金库、ttyd 和附加服务通信

## 4. 核心概念

传统 Linux 桌面：
桌面环境
  ├─ 面板
  ├─ 文件管理器
  ├─ 终端
  ├─ 浏览器
  ├─ 应用菜单
  └─ 设置

XWorkspace 桌面

Chrome / Chromium 桌面 Shell
  └─ AI 工作区门户
      ├─ 智能体控制台
      ├─ 终端
      ├─ VSCode / 代码服务器
      ├─ 文件
      ├─ 模型网关
      ├─ 金库机密
      ├─ 运行时状态
      ├─ 工作流运行器
      ├─ 插件中心
      ├─ 浏览器使用
      └─ 计算机使用


## 5. 显示栈策略

XWorkspace 避免将传统的 X11 桌面体验作为产品界面进行支持。
然而，Chrome / Chromium 仍然需要一个显示栈。
推荐的演进路径：

第一阶段：

使用 XFCE 或轻量级桌面会话，但隐藏传统桌面组件，仅暴露 Chrome / Chromium Shell。

第二阶段：

用一个最小化的窗口管理器替换 XFCE。只有 Chrome / Chromium 作为可见的工作区 Shell 被启动。

第三阶段：

转向 Wayland / Weston / Cage 模式。Chrome / Chromium 成为唯一面向用户的 Shell。


## 访问与暴露策略

XWorkspace 遵循默认安全的访问策略。

默认情况下，XWorkspace 不会将完整的 AI 工作区门户、WebRTC 桌面、ttyd、LiteLLM、金库或其他内部服务直接暴露给公共互联网。

默认的公共入口应被限制为：https://xworkmate-bridge.example.com

此端点在早期阶段受访问令牌 (access token) 保护，并应在未来版本中演进为基于 JWT 的身份验证。

默认访问模型

公共互联网
  ↓
https://xworkmate-bridge.example.com
  ↓
令牌 / 未来 JWT 验证
  ↓
XWorkmate Bridge
  ↓
本地核心服务

AI 工作区门户默认保持本地访问：

Chrome / Chromium 桌面 Shell
  ↓
http://localhost:17000
  ↓
AI 工作区门户


默认不暴露的服务：

- AI 工作区门户
- WebRTC 桌面
- ttyd
- LiteLLM
- Vault
- OpenClaw 网关
- 内部状态端点
- 插件 / 工作流服务

高级用户模式

高级用户可以选择暴露额外的服务，但他们应明确地这样做并配置更强的访问控制。
推荐的高级暴露要求：

- HTTPS

- MFA（多因素认证）
- JWT 身份验证
- IP 白名单（可选）
- 反向代理访问策略
- 审计日志
- 速率限制
- 敏感服务使用独立的子域名
