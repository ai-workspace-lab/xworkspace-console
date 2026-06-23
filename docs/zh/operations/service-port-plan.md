[🇺🇸 English](../../../README.md) | [🇨🇳 中文](../../../README.zh.md)

# XWorkspace 控制台服务端口规划

日期：2026-06-07

本规划基于对 `ubuntu@xworkmate-bridge.svc.plus` (`jp-xhttp-contabo.svc.plus`) 的线上主机检查以及本地 XWorkspace 控制台仓库状态制定。

## 规范端点映射

| 组件 | 绑定 | 端口 | URL | 所有者 | 备注 |
| --- | --- | ---: | --- | --- | --- |
| XWorkspace Console | `127.0.0.1` | `17000` | `http://127.0.0.1:17000` | `xworkspace-console.service` | 规范的仪表板端点。避免与 macOS 上的 `ControlCenter` 发生 `7000` 端口冲突。 |
| XWorkspace Status API | `127.0.0.1` | `8788` | `http://127.0.0.1:8788` | `xworkspace-api.service` | 用于 `/health`、`/services`、`/metrics/simple` 的 Go API。 |
| XWorkmate Bridge | `127.0.0.1` | `8787` | `http://127.0.0.1:8787` | `xworkspace-bridge.service` / 线上 `xworkmate-bridge.service` | 预留给 bridge 控制面。不要在仪表板中重复使用。 |
| OpenClaw Gateway | `127.0.0.1` | `18789` | `http://127.0.0.1:18789/channels` | `xworkspace-openclaw.service` / 线上 `openclaw-gateway.service` | OpenClaw UI 与网关入口。 |
| LiteLLM | `127.0.0.1` | `4000` | `http://127.0.0.1:4000/ui` | `xworkspace-litellm.service` | 线上主机重定向后返回 HTTP 200。 |
| Vault | `0.0.0.0` 或 `127.0.0.1` | `8200` | `http://127.0.0.1:8200` | `xworkspace-vault.service` / 系统 Vault | 线上主机在 `0.0.0.0:8200` 暴露 Vault；如果没有远程客户端需要，则后续收紧至环回地址。 |
| Embedded Terminal | `127.0.0.1` | `7681` | `http://127.0.0.1:7681` | `ttyd.service` 或 `xworkspace-ttyd.service` | 仅使用一个所有者。线上主机已经有系统的 `ttyd.service`；用户级的 `xworkspace-ttyd.service` 因端口冲突而失败。 |
| Legacy Portal | `0.0.0.0` | `7000` | `http://127.0.0.1:7000` | `xworkspace-portal.service` | 已废弃。将由使用 `17000` 的 Console 替代。 |

## 线上主机发现

- `xworkspace-portal.service` 在 `0.0.0.0:7000` 激活，使用 `python3 -m http.server 7000`。
- `xworkspace-chrome.service` 目前使用 `--app=http://localhost:7000` 打开。
- `xworkspace-console.service` 存在但未激活，仍指向旧脚本模式。
- `xworkmate-bridge.service` 在 `127.0.0.1:8787` 激活。
- `openclaw-gateway.service` 在 `127.0.0.1:18789` 激活。
- `xworkspace-litellm.service` 在 `127.0.0.1:4000` 激活。
- Vault 在 `0.0.0.0:8200` 激活。
- 系统 `ttyd.service` 在 `127.0.0.1:7681` 激活。
- 用户 `xworkspace-ttyd.service` 正在自动重启，因为 `7681` 已被占用。

## 迁移顺序

1. 部署 React Console 到 `~/xworkspace-console/dashboard`。
2. 将 `xworkspace-console.service` 替换为在 `127.0.0.1:17000` 运行的常驻服务。
3. 将 Chrome app 模式更改为 `http://127.0.0.1:17000`，并使其依赖于 `xworkspace-console.service`。
4. 在 Console 通过健康检查后，禁用 `xworkspace-portal.service`。
5. 保持 `xworkmate-bridge.service` 在 `127.0.0.1:8787`。
6. 保持 `ttyd` 在 `127.0.0.1:7681`；当系统 `ttyd.service` 处于激活状态时，不要启动 `xworkspace-ttyd.service`。
7. 保持 LiteLLM、Vault 和 OpenClaw 在其现有的线上端口。

## 冲突规则

- 绝不能将 Console 分配到 `7000`；macOS 可能会保留它，而且线上主机已经将其用于废弃的 portal。
- 绝不能将 Console 分配到 `8787`；那是 bridge 控制面的端口。
- 将 `7681` 视为终端单例拥有；若系统 `ttyd.service` 存在则优先使用。
- 除非有反向代理明确暴露，否则所有控制面服务优先绑定环回地址。
