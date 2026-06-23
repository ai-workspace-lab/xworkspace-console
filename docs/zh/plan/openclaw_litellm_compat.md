[🇺🇸 English](../../../README.md) | [🇨🇳 中文](../../../README.zh.md)

# 统一 AI 网关 (LiteLLM) 与 OpenClaw 兼容提供商设计规划

为了保持 OpenClaw 客户端原生的 `provider/model` 语法习惯，同时让所有流量依然经由 LiteLLM 统一网关进行集中鉴权、限流和日志管理，我们对网关映射层进行重构。

## 设计目标
1. 废弃单薄的 `litellm` 提供商，改用在 OpenClaw 中直接配置 `deepseek`、`nvidia`、`ollama` 三大提供商的兼容模式。
2. 这三大提供商在 OpenClaw 的后台配置中，将全部指向 `http://127.0.0.1:4000/v1`（LiteLLM 端点），并使用统一的 `AI_WORKSPACE_AUTH_TOKEN` 进行鉴权。
3. LiteLLM 内部的路由（Alias ID）严格采用 `provider/model` 命名格式，精确匹配三大渠道。这样既绕过了 OpenClaw 的路由拦截，又实现了全通道集中代理。

## 通道映射矩阵

根据目前的 API 接入情况，通道分布规划如下：

### 1. DEEPSEEK_API_KEY (DeepSeek 官方通道)
* `deepseek/deepseek-v4-flash`
* `deepseek/deepseek-v4-pro`
* `deepseek/deepseek-chat`
* `deepseek/deepseek-reasoner`

### 2. NVIDIA_API_KEY (NVIDIA NIM / 代理通道)
* `nvidia/deepseek-v4-flash`
* `nvidia/deepseek-v4-pro`
* `nvidia/glm-5.2`
* `nvidia/minimax-m3`
* `nvidia/qwen3.5`
* `nvidia/kimi-k2.7-code`

### 3. OLLAMA_API_KEY (OLLAMA Cloud / 代理通道)
* `ollama/deepseek-v4-flash`
* `ollama/deepseek-v4-pro`
* `ollama/glm-5.2`
* `ollama/minimax-m3`
* `ollama/qwen3.5`
* `ollama/kimi-k2.7-code`

## 实施细节

1. **LiteLLM 模型注册层 (`register_mainstream_models.sh`)**
   修改 `add_model` 的调用逻辑，按上述矩阵分别在 DeepSeek、NVIDIA 和 OLLAMA 环境变量保护下，注册对应的前缀别名。
   
2. **OpenClaw 网关配置层 (`gateway_openclaw/defaults/main.yml`)**
   - 新增 `deepseek`、`nvidia`、`ollama` 三个 Provider 节点。
   - `api` 统一设定为 `openai-completions`，`baseUrl` 指向 LiteLLM。
   - 移除老旧的 `litellm` 单点配置。
   - 更新 UI 下拉框 `gateway_openclaw_default_models` 囊括所有新通道模型。

## 效果
配置生效后，前端可像原生调用不同渠道一样直观体验（如选定 `NVIDIA` 类别下的 `glm-5.2`），而后台流量全部集中于 LiteLLM 代理中，根除 Auth 解析错误。
