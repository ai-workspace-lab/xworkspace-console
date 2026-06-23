[🇺🇸 English](../../README.md) | [🇨🇳 中文](../../README.zh.md)

# LiteLLM Model Registration Mapping Architecture and Plan

This document records the large model routing and unified mapping architecture of `openclaw` -> `litellm` (AI Gateway) -> `register_mainstream_models.sh`.

## Architecture Principles

1. **Multi-endpoint Native Simulation and Unified Routing**: To be compatible with OpenClaw's native route hijacking feature for different providers, we have deprecated the monolithic `litellm` node in the OpenClaw configuration, and instead directly **simulate the three native providers: `deepseek`, `nvidia`, `ollama`**.
2. **Underlying Convergence**: All API Endpoints and Auth Tokens of these three providers point entirely to the local LiteLLM gateway (`http://127.0.0.1:4000/v1`) and the unified `AI_WORKSPACE_AUTH_TOKEN`. LiteLLM acts as the true gateway, converging various heterogeneous platforms into a unified OpenAI standard format.
3. **Prefix Routing and Precision Striking**: In `register_mainstream_models.sh`, we forcefully add the corresponding `provider/` prefix (e.g. `nvidia/glm-5.2`) to the models of each platform. This naming perfectly bypasses OpenClaw's built-in `No API key found` Provider parsing limitation, allowing requests to seamlessly penetrate and reach the gateway.

## Channel Registration Matrix

To account for resource allocation of different proxy pools/distribution channels, the current architecture designs a full-matrix registration channel. As long as the corresponding environment variable Key is configured, the installation script will immediately register the corresponding node to LiteLLM.

### 1. DEEPSEEK_API_KEY (DeepSeek Official Channel)
Mainly proxies basic models provided by the official:
* `deepseek/deepseek-v4-flash`
* `deepseek/deepseek-v4-pro`
* `deepseek/deepseek-chat`
* `deepseek/deepseek-reasoner`

### 2. NVIDIA_API_KEY (NVIDIA NIM / Proxy Channel)
As a high-speed concurrent or third-party proxy aggregation interface:
* `nvidia/deepseek-v4-flash`
* `nvidia/deepseek-v4-pro`
* `nvidia/glm-5.2`
* `nvidia/minimax-m3`
* `nvidia/qwen3.5`
* `nvidia/kimi-k2.7-code`

### 3. OLLAMA_API_KEY (OLLAMA Cloud / Proxy Channel)
As another alternate distribution channel:
* `ollama/deepseek-v4-flash`
* `ollama/deepseek-v4-pro`
* `ollama/glm-5.2`
* `ollama/minimax-m3`
* `ollama/qwen3.5`
* `ollama/kimi-k2.7-code`

## Updates and Workflow

1. **Set Authentication**: Use commands like `export DEEPSEEK_API_KEY="sk-xxx"` to set target environment variables.
2. **One-click Deployment**: Run `curl -sfL https://install.svc.plus/ai-workspace | bash -` to deploy the entire AI Workspace.
3. **Registration Channels**: The `register_mainstream_models.sh` script is triggered during installation, opening up LiteLLM's routing table based on the keys you configured (non-empty).
4. **Direct Frontend Experience**: After OpenClaw restarts, it will automatically pull the latest category form, and users can directly click on `glm-5.2` or `deepseek-v4-flash` under the category (like NVIDIA) in the UI interface for high-concurrency inference.
