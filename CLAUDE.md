# xworkspace-console — Agent 规范

## GitHub Actions Workflow 编写规则

### 禁止内嵌脚本（shell heredoc / python heredoc）

**严禁**在 `.github/workflows/` 的 `run:` 块里使用任何内嵌 heredoc：

```yaml
# ❌ 禁止 — shell heredoc
run: |
  cat > file.tf << EOF
  content
  EOF

# ❌ 禁止 — python 内联 heredoc
run: |
  python3 - <<'PYEOF'
  import os
  ...
  PYEOF
```

**原因：**
- Shell heredoc 内容从列 1 开始，超出 YAML literal block 缩进范围，导致整个 workflow 文件 YAML 解析失败，GitHub 丢失 `on:` 触发器。
- Python 内联 heredoc 同理，且难以维护和测试。

**正确做法：外置脚本，workflow 只做调用。**

```yaml
# ✅ 正确 — 外置 Python 脚本（放在 infra repo，通过已有 checkout 引用）
- name: generate.py render (YAML -> 显式 HCL + tfvars)
  working-directory: ${{ env.VPS_ROOT }}
  env:
    TF_STATE_ENDPOINT: ${{ steps.vault.outputs.TF_STATE_ENDPOINT }}
    TF_STATE_REGION: ${{ steps.vault.outputs.TF_STATE_REGION }}
  run: python3 scripts/generate.py render
```

渲染脚本存放在 `ai-workspace-infra/iac_modules/terraform-hcl-standard/vultr-vps/scripts/`，
通过 workflow 内已有的 `Checkout iac_modules` 步骤引用，无需额外 self-checkout。
workflow 内的 `run:` 块调用外置脚本，命名规范 `动词_名词.py` 或 `动词-名词.sh`。

### 其他规范

- workflow 使用的外置脚本必须在 `scripts/` 目录下，不得内嵌在 `run:` 块里。
- workflow 文件修改后必须用 `python3 -c "import yaml; yaml.safe_load(open(...))"` 验证 YAML 语法再提交。
- 不使用 GitHub Actions Secrets，所有机密统一从 Vault (https://vault.svc.plus) OIDC 读取。
