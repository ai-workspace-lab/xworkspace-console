[🇺🇸 English](../../README.md) | [🇨🇳 中文](../../README.zh.md)

# AI Workspace Runtime 交付规划

> 目标：把 `setup-ai-workspace-all-in-one.sh` 从“一组分散的基础设施 Playbook”收敛为一个**可直接使用的 AI Workspace Runtime 产品**——版本受控、运行模式可组合、对外仅暴露 Bridge、部署完成后输出一次性统一摘要。
>
> 本文是落地前的详细规划（设计 + 变更清单 + 提交/部署/验收方案）。实现阶段严格按本文执行，不扩大修改范围、不做大规模重构、优先复用现有实现。

- 状态：Linux 离线包链路与 macOS 本地校验链路已进入联调阶段；macOS 已越过多数 role 兼容性阻塞，当前重点是 LiteLLM 离线 runtime 接入、完整安装复跑和幂等验收
- 影响仓库：`ai-workspace-infra/playbooks`、`ai-workspace-lab/xworkspace-console`、`ai-workspace-lab/xworkspace-core-skills`、`ai-workspace-services/qmd`、`ai-workspace-services/litellm`
- 目标主机：`root@acp-bridge.onwalk.net`
- 对外默认域名（唯一公开服务）：`acp-bridge.onwalk.net`

## TODO

- [x] 等待并核对 `xworkspace-console` 的离线包 GitHub Actions 发布链路，确认 `publish-release` 完整结束且 release 产物上传成功。
- [ ] 继续核对 `root@acp-bridge.onwalk.net` 的远程部署进度，确认 `setup-ai-workspace-all-in-one.sh` 最终完成并输出统一摘要。
- [x] `setup-ai-workspace-all-in-one.sh` 在目标主机上优先使用离线安装包加速部署，减少在线拉取与安装耗时。
- [x] 为 LiteLLM 新增 runtime wheelhouse release workflow，供 all-in-one 离线包消费。
- [ ] 验证 `ai-workspace-services/litellm` 的 runtime release 实际生成成功，并确认 console 离线包能下载 matching `litellm-runtime-<distro>-<version>-<arch>.tar.gz`。
- [ ] 验证 `setup-ai-workspace-all-in-one.sh` 幂等性：同一主机连续执行两次均成功，复用凭据、离线包缓存与已导入镜像，并安全等待部署/APT 锁。
- [ ] 完成 macOS 本地最终验收核对：Portal、Bridge、OpenClaw、QMD、Hermes、PostgreSQL、Vault、LiteLLM 状态正常，`http://localhost:8181/mcp` 和 LiteLLM health 可达。
- [ ] 完成远程 Linux 最终验收核对：Bridge 对外可达、其余服务默认仅本地监听、`acp-codex` / `opencode` / `gemini` / `hermes` / `qmd` / `litellm` 状态正常。
- [ ] 记录最终提交哈希、GitHub Actions run、release tag 与远端验证结果，回填到本计划的交付结果部分。

---

## 6. 仓库与提交计划

| 仓库 | 主要改动 | Commit message（建议） | 推送目标 |
|---|---|---|---|
| `playbooks` | 角色拆分、版本固定、Bridge 域名、运行模式守卫、PG compose、QMD/LiteLLM 源、聚合链去重、本规划文档 | `feat: deliver versioned AI Workspace Runtime (role split, run-mode matrix, bridge domain)` | `ai-workspace-infra/playbooks` |
| `xworkspace-console` | `setup-ai-workspace-all-in-one.sh` 统一摘要、pull 源对齐、console 默认不公开 | `feat: unified one-time deploy summary + bridge-only public surface` | `ai-workspace-lab/xworkspace-console` |
| `xworkspace-core-skills` | （按需）技能种子/版本对齐 | `chore: align skills seed for workspace runtime` | `ai-workspace-lab/xworkspace-core-skills` |

> 每个仓库**独立提交**，分别记录 Commit Hash 写入最终交付说明。

### 6.1 当前实现进度（2026-06-22）

| 仓库 | 已完成进展 | 已知待处理 |
|---|---|---|
| `ai-workspace-infra/playbooks` | OpenClaw doctor/restart 已拆分；QMD 已补 macOS LaunchAgent；OpenClaw `acpx` 兼容性 assert 已修；LiteLLM 已切 Python 3.13 venv、安装探测和 `.install-spec` 跳过重复安装 | 需要完整 macOS 复跑确认 `qmd :8181/mcp`、OpenClaw registry、LiteLLM health；需要确认 all-in-one 的 macOS patch 与 playbooks main 不再互相覆盖 |
| `ai-workspace-lab/xworkspace-console` | all-in-one 离线包链路已能消费 console/bridge/qmd/litellm runtime release；macOS 调试案例持续记录在 `docs/case/macos_compatibility_tests.md` | `uninstall purge` 仍需打印删除路径；需要清理离线包生成目录等非源码正式目录；需要确认 `install.svc.plus/ai-workspace` 发布入口同步到最新 main |
| `ai-workspace-services/qmd` | all-in-one 离线包脚本按 `qmd-runtime-linux-${ARCH}.tar.gz` 消费 release；playbooks 已补 QMD macOS LaunchAgent | 需要确认 latest runtime release 与 offline package 拉取路径持续可用；macOS 需实测 MCP endpoint |
| `ai-workspace-services/litellm` | 新增 `.github/workflows/offline-package-litellm-runtime.yaml`，产出 `litellm-runtime-<distro>-<version>-<arch>.tar.gz`、wheelhouse、可选 portable Python、`metadata/runtime.env` | 需要触发 GitHub Actions 并确认 release asset 与 `SHA256SUMS`；需要确认 console 离线包使用 `latest-runtime` 能解析到该 release |
| `ai-workspace-lab/xworkspace-core-skills` | all-in-one 离线包仍按 core-skills repo/ref 打包 | 当前未发现新的 macOS 阻塞；最终验收仍需确认技能注入与 OpenClaw/QMD 可见 |

### 6.2 近期关键提交

| 仓库 | Commit | 说明 |
|---|---|---|
| `ai-workspace-infra/playbooks` | `09a39e6` | `perf(openclaw): avoid unnecessary doctor repairs` |
| `ai-workspace-infra/playbooks` | `f01e0bb` | `fix(qmd): provision macOS LaunchAgent` |
| `ai-workspace-infra/playbooks` | `c11f51b` | `fix(openclaw): allow version-matched acpx plugin` |
| `ai-workspace-infra/playbooks` | `71ebe64` | `fix(litellm): isolate runtime in Python 3.13 venv` |
| `ai-workspace-infra/playbooks` | `6a2f05f` | `fix(litellm): skip redundant dependency installs` |
| `ai-workspace-services/litellm` | `51cde5e32` | `ci: add offline litellm runtime workflow` |

### 6.3 当前最需要收口的问题

1. `LiteLLM`：在线 `pip install litellm[proxy]` 仍可能因大 wheel 下载中断失败；应以 runtime wheelhouse release 作为 all-in-one 默认加速路径，并保留在线路径为 fallback。
2. `install.svc.plus/ai-workspace`：需要确认公开短链实际拉到的是 `xworkspace-console@main` 最新脚本，否则 macOS 仍可能运行旧 bootstrap。
3. `uninstall purge`：需要输出将删除/已删除/不存在的路径，覆盖 macOS 与 Linux 的 token、Vault/OpenClaw 状态、临时部署目录、系统配置目录。
4. 工作区清理：需要清理 `ai-workspace-all-in-one-offline-*` 等生成目录，避免离线包产物混入源码根目录。
5. 最终验收：需要在 macOS 上做一次干净安装和一次重复安装，记录各服务端口、LaunchAgent/systemd 状态、health endpoint 与 changed 统计。

---

## 8. 风险与回退

| 风险 | 缓解 / 回退 |
|---|---|
| 沙箱无法直连 GitHub/目标主机 | 本地完成代码+提交；push 与远程部署由有网络的环境执行 |
| PG 切 compose 影响既有数据 | 保留 `postgresql_deploy_mode=native` 回退路径 |
| 角色拆分回归 | `setup-xfce-xrdp.yaml` 组合两角色，行为等价；保留旧角色直至引用切换验证通过 |
| 版本固定导致拉取失败 | 版本变量集中、可单点覆盖（env / `-e`） |

---

## 9. 实现顺序（落地次序）

1. 本规划文档入库（docs/）。
2. 角色拆分 + `setup-xfce-xrdp.yaml` 组合。
3. 版本固定（OpenClaw/Vault/Hermes/QMD/LiteLLM/Node/Playwright/Chrome）。
4. Bridge 域名参数透传（`XWORKMATE_BRIDGE_DOMAIN`，自定义，不改 role 默认）。
5. 运行模式守卫 + PG compose 默认。
6. 聚合链去重（Hermes）+ console 默认不公开。
7. `setup-ai-workspace-all-in-one.sh` 统一摘要。
8. 三仓库分别提交，记录 Commit Hash。
9. 推送 + 远程部署 + 按 §7.2 验证。
10. 并发优化落地（见 §10），最后做 §10.8 等价性回归。

---

