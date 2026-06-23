[🇺🇸 English](../../../README.md) | [🇨🇳 中文](../../../README.zh.md)

# XWorkspace 控制台主页 V1

日期：2026-06-07
状态：初次实施设计

## 目标

基于提供的控制平面设计参考，构建 `xworkspace-console` 主页的第一个 React 实现。

第一个版本可以使用临时的模拟数据，但组件结构必须为真正的运行时集成做好准备：

- 自定义选项卡
- 服务状态
- 活跃的 Agent
- 最近任务
- 制品
- 系统健康状态
- 嵌入式 `ttyd`
- 快速访问链接
- 系统遥测集成点

## 信息架构

主页围绕操作仪表板进行组织：

- 左侧导航
  - 工作区 (Workspace)
  - 仪表板 (Dashboard)
  - Agent
  - 任务 (Tasks)
  - 制品 (Artifacts)
  - OpenClaw
  - Bridge
  - LiteLLM
  - Vault
  - 运行时 (Runtime)
  - 终端 (Terminal)
  - 设置 (Settings)
- 顶部状态栏
  - CPU
  - GPU
  - VPN 状态
  - 通知
  - 用户/个人资料
- 主概览
  - 指标卡片
  - 服务状态
  - 活跃的 Agent
  - 最近任务
  - 制品
  - 系统健康状态
  - 快速访问

## 必需链接

以下导航和快速访问目标对于 V1 是规范的：

- OpenClaw: `http://127.0.0.1:18789/channels`
- Vault: `http://127.0.0.1:8200`
- LiteLLM: `http://127.0.0.1:4000/ui`
- 终端: `http://127.0.0.1:7681`

## 自定义选项卡

选项卡应表示为数据，而不是在整个 UI 中硬编码。

初始选项卡形态：

```ts
type Tab = {
  id: string;
  label: string;
  href: string;
  kind: 'internal' | 'external' | 'embed';
};
```

这允许主页稍后支持从 YAML 或 API 响应中获取的用户定义的选项卡。

## 嵌入式终端

终端选项卡应渲染一个真正的 `ttyd` 嵌入：

```text
http://127.0.0.1:7681
```

第一个实现可以使用 iframe。如果需要，后续版本可以对终端进行代理或身份验证。

## 系统探针

主页的设计应能消费来自 Go API 和相关可观测性工具的本地状态数据。

初始本地 API：

- `GET http://127.0.0.1:8788/health`
- `GET http://127.0.0.1:8788/services`
- `GET http://127.0.0.1:8788/metrics/simple`

未来的集成：

- Prometheus 指标
- Vector 日志
- 本地服务日志
- Agent 就绪探针
- Vault 连接状态
- OpenClaw 网关状态

## 模拟数据策略

V1 可以在以下方面使用模拟数据：

- 指标卡片
- Agent
- 任务
- 制品
- 系统健康评分

V1 应该在可用时尝试从 Go API 读取 `/services`，并在失败时优雅地回退到模拟的服务行。

## 视觉方向

提供的设计参考使用了明亮、整洁的操作控制台风格：

- 白色面板
- 蓝色主要操作色
- 细微的边框
- 紧凑的表格
- 低噪点的状态指示器
- 适度的圆角
- 仪表板优先的布局，而不是营销页面

卡片仅应被用于重复的仪表板项目和有界限的面板中。

## V1 实施说明

实施位置：

- `dashboard/src/main.tsx`
- `dashboard/src/styles.css`

V1 包含：

- 模拟指标
- 模拟 Agent
- 模拟任务
- 模拟制品
- OpenClaw、Vault、LiteLLM 的真实外部链接
- 嵌入式的 `ttyd` 终端选项卡
- 尝试从 `http://127.0.0.1:8788/services` 获取服务状态

## 下一步

- 将选项卡定义移动到 `config/xworkspace-desktop.yaml`
- 向 Go API 添加 `/tabs` 端点
- 如果仪表板和 API 从不同的端口提供服务，添加 CORS 支持
- 添加真实的 CPU、内存、磁盘和网络主机指标
- 添加 Prometheus 和 Vector 探针
- 用正式的图标系统替换字母占位符
```
