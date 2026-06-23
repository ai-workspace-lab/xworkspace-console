# LiteLLM 模型注册映射架构与规划

本文档记录了 `openclaw` -> `litellm` (AI Gateway) -> `register_mainstream_models.sh` 的大模型路由和统一映射架构。

## 架构原则

1. **多端原生模拟与统一路由**：为了兼容 OpenClaw 对不同提供商（Provider）原生路由劫持的特性，我们在 OpenClaw 配置中废弃了单体的 `litellm` 节点，转而直接**模拟原生的 `deepseek`、`nvidia`、`ollama` 三大提供商**。
2. **底层收口**：这三大提供商的所有 API Endpoint 和 Auth Token 全部指向本地的 LiteLLM 网关（`http://127.0.0.1:4000/v1`）以及统一的 `AI_WORKSPACE_AUTH_TOKEN`。LiteLLM 充当真正的网关，将各异构平台收口为统一的 OpenAI 标准格式。
3. **前缀路由与精确打击**：在 `register_mainstream_models.sh` 中，我们为各平台的模型强制加上对应的 `provider/` 前缀（如 `nvidia/glm-5.2`）。这种命名完美绕过了 OpenClaw 自带的 `No API key found` 的 Provider 解析限制，让请求无缝穿透抵达网关。

## 渠道注册矩阵

为了兼顾不同代理池/分发渠道的资源配给，目前的架构设计了全矩阵的注册通道。只要配置了相应的环境变量 Key，安装脚本就会立刻向 LiteLLM 注册对应的节点。

### 1. DEEPSEEK_API_KEY (DeepSeek 官方通道)
主要代理官方提供的基础模型：
* `deepseek/deepseek-v4-flash`
* `deepseek/deepseek-v4-pro`
* `deepseek/deepseek-chat`
* `deepseek/deepseek-reasoner`

### 2. NVIDIA_API_KEY (NVIDIA NIM / 代理通道)
作为高速并发或者第三方代理聚合接口：
* `nvidia/deepseek-v4-flash`
* `nvidia/deepseek-v4-pro`
* `nvidia/glm-5.2`
* `nvidia/minimax-m3`
* `nvidia/qwen3.5`
* `nvidia/kimi-k2.7-code`

### 3. OLLAMA_API_KEY (OLLAMA Cloud / 代理通道)
作为另一个备用的分发通道：
* `ollama/deepseek-v4-flash`
* `ollama/deepseek-v4-pro`
* `ollama/glm-5.2`
* `ollama/minimax-m3`
* `ollama/qwen3.5`
* `ollama/kimi-k2.7-code`

## 更新与工作流

1. **设置鉴权**：使用 `export DEEPSEEK_API_KEY="sk-xxx"` 等命令设置目标环境变量。
2. **一键部署**：运行 `curl -sfL https://install.svc.plus/ai-workspace | bash -` 部署整个 AI Workspace。
3. **注册通道**：`register_mainstream_models.sh` 脚本在安装时被触发，根据你所配置的密钥（非空）打通 LiteLLM 的路由表。
4. **前端直接体验**：OpenClaw 重启后会自动拉取最新的分类表单，用户可以在 UI 界面中直接在分类（如 NVIDIA）下点选 `glm-5.2` 或 `deepseek-v4-flash` 进行高并发推断。
