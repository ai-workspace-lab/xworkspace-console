[🇺🇸 English](../../../README.md) | [🇨🇳 中文](../../../README.zh.md)

# Unified AI Gateway (LiteLLM) and OpenClaw Compatible Providers Design Plan

To maintain the OpenClaw client's native `provider/model` syntax habits, while still routing all traffic through the unified LiteLLM gateway for centralized authentication, rate limiting, and log management, we are refactoring the gateway mapping layer.

## Design Goals
1. Deprecate the thin `litellm` provider, and switch to a compatible mode directly configuring the three major providers `deepseek`, `nvidia`, and `ollama` in OpenClaw.
2. In the backend configuration of OpenClaw, these three major providers will all point to `http://127.0.0.1:4000/v1` (LiteLLM endpoint), and use the unified `AI_WORKSPACE_AUTH_TOKEN` for authentication.
3. The routing (Alias ID) inside LiteLLM strictly adopts the `provider/model` naming format, exactly matching the three major channels. This not only bypasses OpenClaw's routing interception, but also achieves full-channel centralized proxying.

## Channel Mapping Matrix

Based on current API access, the channel distribution plan is as follows:

### 1. DEEPSEEK_API_KEY (DeepSeek Official Channel)
* `deepseek/deepseek-v4-flash`
* `deepseek/deepseek-v4-pro`
* `deepseek/deepseek-chat`
* `deepseek/deepseek-reasoner`

### 2. NVIDIA_API_KEY (NVIDIA NIM / Proxy Channel)
* `nvidia/deepseek-v4-flash`
* `nvidia/deepseek-v4-pro`
* `nvidia/glm-5.2`
* `nvidia/minimax-m3`
* `nvidia/qwen3.5`
* `nvidia/kimi-k2.7-code`

### 3. OLLAMA_API_KEY (OLLAMA Cloud / Proxy Channel)
* `ollama/deepseek-v4-flash`
* `ollama/deepseek-v4-pro`
* `ollama/glm-5.2`
* `ollama/minimax-m3`
* `ollama/qwen3.5`
* `ollama/kimi-k2.7-code`

## Implementation Details

1. **LiteLLM Model Registration Layer (`register_mainstream_models.sh`)**
   Modify the invocation logic of `add_model`, registering corresponding prefix aliases under the protection of DeepSeek, NVIDIA, and OLLAMA environment variables respectively according to the matrix above.
   
2. **OpenClaw Gateway Configuration Layer (`gateway_openclaw/defaults/main.yml`)**
   - Add three new Provider nodes: `deepseek`, `nvidia`, and `ollama`.
   - The `api` is uniformly set to `openai-completions`, and `baseUrl` points to LiteLLM.
   - Remove the old `litellm` monolithic configuration.
   - Update the UI dropdown `gateway_openclaw_default_models` to encompass all new channel models.

## Effects
After the configuration takes effect, the frontend can intuitively experience different channels like native calls (such as selecting `glm-5.2` under the `NVIDIA` category), while all backend traffic is centralized in the LiteLLM proxy, eradicating Auth parsing errors.
