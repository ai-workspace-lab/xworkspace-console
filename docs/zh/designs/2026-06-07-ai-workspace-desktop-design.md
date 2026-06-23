[🇺🇸 English](../../../README.md) | [🇨🇳 中文](../../../README.zh.md)

# AI Workspace 桌面设计

日期：2026-06-07
项目：`xworkspace-console`
状态：实施对齐草案

## 1. 概述

本文档定义了基于 XFCE 构建的 AI Workspace 桌面环境的目标设计，其中 `xworkspace-console` 作为合并的实现仓库。

我们的目标不是构建一个新的桌面环境。目标是通过组合以下内容，组装一个极简、可靠的 AI 工作区 shell：

- XFCE 作为桌面基础层
- XFCE 面板和兼容 GTK/XDG 的配置用于桌面界面
- `Plank` 作为首选的自动隐藏停靠栏 (Dock)
- `systemd --user` 用于每个用户的服务编排
- `Go` 用于本地状态收集 API
- `React + Vite + TypeScript` 用于仪表板 UI
- `ttyd` 用于嵌入式终端界面
- `Chrome` 或 `Chromium` 应用程序模式作为主要操作员入口点

预期的视觉方向是一个低干扰的工作区，感觉更接近 NomadBSD、ChromeOS 和简化的 macOS Dock 设置，而不是传统的 Linux 桌面。

## 2. 产品目标

桌面启动后应进入一个专注的 AI 操作环境，其中基于浏览器的控制平面是主要的用户体验。

主要成果：

- 用户登录 XFCE 后进入一个极简工作区，而不是经典的 Linux 桌面
- 顶部状态栏仅显示基本的运行时状态
- 底部停靠栏提供对固定操作员工具集的快速访问
- 浏览器直接打开 XWorkspace 控制平面
- OpenClaw、Bridge、LiteLLM、Vault 和 console 服务通过 systemd 进行管理和检查
- 控制平面可显示本地服务运行状况、基本主机指标和终端访问

## 3. 非目标

第一阶段明确避免以下方向：

- 没有自定义窗口管理器
- 没有自定义桌面 shell 框架
- 没有完整的桌面主题引擎
- 没有 KDE 或 GNOME 依赖项
- 没有将传统的应用程序启动器菜单作为主要交互模型
- 没有桌面小部件或图标混乱
- 不尝试用新的合成器或 shell 替换 XFCE 内部组件

## 4. 用户体验

### 4.1 桌面体验

默认的桌面会话应该给人一种有针对性的、类似设备的感觉：

- 顶部面板高度在 28px 和 32px 之间
- 顶部面板左侧显示 `XWorkspace`
- 右侧显示紧凑的指示器：CPU、内存、网络、Agent 就绪状态、Vault 状态和时间
- 没有桌面图标
- 没有可见的应用程序菜单
- 底部停靠栏默认隐藏，鼠标指向屏幕边缘时显示
- 停靠栏条目是固定的、基于角色的，不是开放式的

### 4.2 停靠栏条目

首选的第一组停靠栏操作是：

- 浏览器
- 终端
- 文件
- VS Code
- XWorkmate
- OpenClaw

这些启动器应该指向稳定的系统二进制文件或应用程序模式 URL，而不是临时的用户 shell 别名。

### 4.3 浏览器条目

主要的操作员 shell 是 Chrome 或 Chromium 应用程序模式：

- 首选默认 URL：`http://127.0.0.1:17000`
- 备用部署 URL：`https://workspace.local`

应用程序模式的启动路径应封装在脚本中，而不是在自动启动和服务文件之间复制。

## 5. 架构

设计分为五层：

1. 桌面 shell 层
2. 服务编排层
3. 本地状态 API 层
4. 仪表板 UI 层
5. 部署/配置层

### 5.1 桌面 Shell 层

此层由以下组成：

- XFCE 会话
- XFCE 顶部面板
- GTK/XDG 配置文件
- Plank 停靠栏
- XDG 自动启动条目

职责：

- 强制执行最小的桌面布局
- 禁用桌面图标和传统菜单混乱
- 暴露稳定的操作员 shell
- 保持与标准 Linux 工具的兼容性

### 5.2 服务编排层

此层使用 `systemd --user`。

管理的服务：

- `xworkspace-console.service`
- `xworkspace-openclaw.service`
- `xworkspace-bridge.service`
- `xworkspace-litellm.service`
- `xworkspace-vault.service`

职责：

- 服务启动顺序
- 重启策略
- 面向操作员的单元命名
- 通过 `systemctl --user` 进行本地自省

### 5.3 本地状态 API 层

此层用 `Go` 编写。

职责：

- 为仪表板暴露健康端点
- 标准化来自 systemd 的服务状态
- 收集简单的主机指标
- 响应来自本地仪表板的轻量级轮询流量

端点：

- `/health`
- `/services`
- `/metrics/simple`

API 应该有意保持小巧和本地优先。

### 5.4 仪表板 UI 层

此层使用 `React + Vite + TypeScript` 编写。

职责：

- 渲染服务卡片
- 在 MVP 中渲染任务和 Agent 占位符
- 展示制品和设置部分
- 通过 `ttyd` 嵌入或链接终端访问
- 充当默认浏览器控制平面

视觉语言应偏暗、精确、侧重操作性，而不是装饰性。

### 5.5 部署和配置层

此层使用：

- Shell 脚本
- YAML 配置
- XFCE XML 模板
- systemd 服务文件

仓库应维护一个人类可读的 YAML 配置文件，用于桌面级默认设置，如端口、浏览器偏好和服务命名。如果 XFCE 和 XDG 需要，生成或复制的运行时文件仍然可以是 XML 或 `.desktop` 文件。

## 6. 规范仓库结构

合并后的仓库应保持以下结构：

```text
xworkspace-console/
├─ api/
├─ assets/
│  ├─ icons/
│  ├─ themes/
│  └─ wallpaper/
├─ config/
│  ├─ autostart/
│  ├─ systemd/
│  │  └─ user/
│  ├─ xfce4/
│  └─ xworkspace-desktop.yaml
├─ dashboard/
│  ├─ src/
│  ├─ package.json
│  ├─ tsconfig.json
│  └─ vite.config.ts
├─ docs/
│  └─ designs/
├─ scripts/
│  ├─ reset-xfce-profile.sh
│  ├─ setup-xworkspace-desktop.sh
│  └─ start-chromium-console.sh
└─ README.md
```

移出范围：

- Flutter
- Dart
- 静态 web shell 冗余

## 7. 命名模型

该仓库统一使用 `xworkspace-console` 作为主要的控制平面名称。

命名决定：

- 保留：`xworkspace-console`
- 保留：`xworkspace-openclaw`
- 保留：`xworkspace-bridge`
- 保留：`xworkspace-litellm`
- 保留：`xworkspace-vault`
- 仅作为历史/重叠标签对待：`xworkspace-dashboard`、`xworkspace-portal`

理由：

- `console` 足够宽泛，涵盖桌面 shell 加上浏览器控制平面
- 一旦服务编排和桌面问题合并，`dashboard` 就显得过于狭隘
- `portal` 与特定的 Web 界面重叠，会导致命名重复

## 8. 在线环境对齐

实时参考主机为：

- SSH 入口：`ubuntu@xworkmate-bridge.svc.plus`
- 实际主机：`jp-xhttp-contabo.svc.plus`

已观察到的参考在线服务行为：

### 8.1 Bridge

线上单元：

- `xworkmate-bridge.service`

观察到的形态：

- `WorkingDirectory=/opt/cloud-neutral/xworkmate-bridge`
- `ExecStart=/home/ubuntu/.local/bin/xworkmate-go-core serve --listen 127.0.0.1:8787`

### 8.2 OpenClaw

线上单元：

- `openclaw-gateway.service`

观察到的形态：

- `WorkingDirectory=/home/ubuntu`
- `ExecStart=/home/ubuntu/.local/bin/openclaw gateway run --port 18789 --force`

### 8.3 含义

本地仓库应在服务模板中保留这些真实的启动模式，即使仓库级名称被标准化为：

- `xworkspace-bridge.service`
- `xworkspace-openclaw.service`

这可防止桌面仓库偏离线上环境。

## 9. Systemd 设计

### 9.1 单元

必需的用户单元：

- `xworkspace-console.service`
- `xworkspace-openclaw.service`
- `xworkspace-bridge.service`
- `xworkspace-litellm.service`
- `xworkspace-vault.service`

稍后推荐的可选单元：

- `xworkspace-status-api.service`
- `xworkspace-ttyd.service`

### 9.2 服务规则

每个服务都应定义：

- 明确的 `Description`
- 当依赖网络就绪时使用 `After=network-online.target`
- `Restart=always`
- 当运行时行为依赖于工作目录时，显式使用 `WorkingDirectory`
- 当工具路径或配置重要时，显式添加 `Environment=` 条目

### 9.3 Console 服务

在 MVP 中，`xworkspace-console.service` 应运行 React 仪表板的 dev server，但预期的演进是：

- 早期迭代期间的 dev 模式
- 稍后由轻量级本地 Web 服务器提供的已构建静态资源

该未来的转变不应改变服务名称。

## 10. YAML 配置模型

主要配置文件：

- `config/xworkspace-desktop.yaml`

职责：

- 浏览器二进制文件选择
- 仪表板 URL 和端口
- 服务命名默认值
- Shell 级别的 UI 默认设置，如停靠栏策略和面板高度

设置脚本应读取此 YAML 并使用它在合理的情况下修补或生成面向部署的文件。

## 11. XFCE 和主题配置

### 11.1 XFCE

配置模板应保留在 `config/xfce4/` 中。

关键职责：

- 面板放置
- 面板大小
- 快捷键默认值
- 会话行为
- 窗口焦点默认值

### 11.2 GTK / XDG

主题定制应保持轻量级：

- GTK 主题选择
- 图标主题选择
- XDG 自动启动条目
- 桌面图标抑制

MVP 中不需要大型主题子系统。

## 12. 仪表板 MVP

### 12.1 各个部分

仪表板应公开以下部分：

- 服务 (Services)
- 任务 (Tasks)
- Agent
- 制品 (Artifacts)
- 终端 (Terminal)
- 设置 (Settings)

### 12.2 终端

终端行为应为以下之一：

- 嵌入式的 `ttyd` 框架
- 链接到 `ttyd` 的本地跳转链接

MVP 可以从嵌入式面板或链接了状态的 shell 区域开始。

### 12.3 视觉方向

界面应遵循：

- 深色背景
- 蓝色/白色操作强调色
- 低视觉噪音
- 合理的间距和可读的密度
- 像设备一样的专注度，而非营销美学

卡片仅应被用于重复的仪表板项目和有界限的面板中。

## 13. Go API MVP

### 13.1 端点

- `/health`
  - 状态、架构、操作系统、CPU 数量、服务快照
- `/services`
  - 标准化的 systemd 服务状态
- `/metrics/simple`
  - 机器可读的指标行输出

### 13.2 数据源

MVP 可以使用：

- `systemctl --user is-active`
- 仅使用标准库 HTTP
- 简单的主机运行时自省

后续版本可能会添加：

- CPU 百分比
- 内存使用率
- 磁盘使用率
- 网络可用性
- Agent 就绪探针

## 14. 设置和重置流程

### 14.1 设置

`scripts/setup-xworkspace-desktop.sh` 应该：

- 安装所需的包
- 创建目标配置目录
- 复制 XFCE 和 systemd 模板
- 复制 XDG 自动启动条目
- 启用相关的用户服务

### 14.2 重置

`scripts/reset-xfce-profile.sh` 应该：

- 移除复制的 XFCE 面板/会话配置
- 移除 XWorkspace 自动启动条目
- 移除 XWorkspace 用户服务文件和符号链接

重置路径必须避免破坏无关的 shell 配置。

## 15. 风险和限制

### 15.1 浏览器二进制变体

不同的 Debian/Ubuntu 变体可能会提供：

- `google-chrome`
- `chromium-browser`
- `chromium`

启动器必须至少支持一个首选二进制文件加上后备选项。

### 15.2 XFCE 插件可用性

停靠栏策略可能因发行版打包而异：

- 首选 `Plank`
- 需要时使用 `xfce4-docklike-plugin` 作为后备

### 15.3 Dev Server 对比静态构建

在 MVP 中运行 Vite 开发模式是可以接受的，但长远来看，如果将仪表板构建并作为静态文件提供，桌面可靠性会提高。

### 15.4 线上漂移

桌面仓库必须定期根据线上主机重新验证服务模板，以避免过时的假设，特别是针对：

- OpenClaw 启动标志
- bridge 二进制路径
- 与授权相关的环境变量

## 16. 实施路线图

### 阶段 1

- 移除 Flutter/Dart 残留物
- 仅保留 YAML + Go + React + XFCE/systemd
- 将 openclaw 和 bridge 服务模板与线上主机会齐
- 将仪表板保持为本地 Vite MVP

### 阶段 2

- 向 Go API 添加真实的主机指标
- 向仪表板添加 `ttyd` 集成
- 添加基于 YAML 配置生成的停靠栏/面板设置行为
- 改进 Plank 自动隐藏设置和启动器配置

### 阶段 3

- 打包为 Debian 制品
- 准备 ISO/bootstrap 路径
- 将仪表板服务从开发模式切换到生产静态资产

## 17. 验收标准

满足以下条件时，桌面环境被认为在 MVP 中是可以接受的：

1. 一个干净的 Ubuntu 或 Debian 虚拟机可以成功运行设置脚本
2. XFCE 加载到极简的 workspace shell
3. 桌面图标被隐藏
4. 传统的应用程序菜单不是工作流程的核心
5. 浏览器应用模式自动打开 XWorkspace console
6. 仪表板可以读取本地服务运行状况
7. 重置脚本可以回滚 XWorkspace 特定的桌面变更
8. 标准的终端、浏览器和文件管理器行为保持完整

## 18. 当前仓库方向

截至此设计草案，`xworkspace-console` 应被视为：

- 规范的合并仓库
- 桌面 shell 模板的来源
- systemd 服务模板的来源
- Go 本地 API 的来源
- React 仪表板的来源

该设计取代了早期的 Flutter 控制台仓库、静态 portal 概念和单独的桌面骨架之间的划分。
