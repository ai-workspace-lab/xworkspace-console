[🇺🇸 English](../../../README.md) | [🇨🇳 中文](../../../README.zh.md)

# macOS Compatibility Deployment Test Cases

This document records the cross-platform compatibility issues encountered and their fix solutions during the fully automated deployment of `setup-ai-workspace-all-in-one.sh` in the macOS (Darwin) environment.

## Core Background

The original script and Ansible Playbooks were designed for Debian/Ubuntu Linux, strongly relying on `root` permissions, the `apt` package manager, system directories (`/usr/local/sbin`, `/etc/systemd`), and default user paths (`/home/ubuntu`). Deploying in unprivileged mode on macOS triggered a massive amount of permission and path exceptions.

---

## TC-MAC-001: TTYD Binary and Path Exceptions

| Item | Content |
|------|------|
| **Trigger File** | `setup-ai-workspace-all-in-one.sh` |
| **Trigger Error** | The script attempts to download the ttyd binary and write it to `/usr/local/bin/ttyd`, but lacks permissions and the architecture mismatches |
| **Fix Solution** | Intercept binary download under Darwin, switch to `brew install ttyd`; use `command -v ttyd` to dynamically resolve the path |

## TC-MAC-002: Global Privilege Escalation (Sudo) Blocking

| Item | Content |
|------|------|
| **Trigger File** | `setup-ai-workspace-all-in-one.sh` → Ansible Playbook |
| **Trigger Error** | `sudo: a password is required` |
| **Fix Solution** | Inject `--extra-vars "ansible_become=false"` under Darwin to cancel automatic privilege escalation |

## TC-MAC-003: Default User Group Allocation Failure

| Item | Content |
|------|------|
| **Trigger File** | `setup-xworkspace-console.yaml` |
| **Trigger Error** | `chown` cannot find the `ubuntu` group |
| **Fix Solution** | Conditional rendering: `"{{ 'staff' if ansible_os_family == 'Darwin' else 'ubuntu' }}"` |

## TC-MAC-004: Hardcoded Paths

| Item | Content |
|------|------|
| **Trigger File** | `setup-xworkspace-console.yaml` Header Variables Area |
| **Trigger Error** | `cd /home/ubuntu/xworkspace-console/dashboard: No such file or directory` |
| **Fix Solution** | Refactor `xworkspace_console_home` to `{{ ansible_env.HOME }}`, and chain-evaluate all derived directories |

## TC-MAC-005: Template Engine Rendering Exception (Undefined Variable)

| Item | Content |
|------|------|
| **Trigger File** | `console.plist.j2` |
| **Trigger Error** | `AnsibleUndefinedVariable: 'nodejs_version' is undefined` |
| **Fix Solution** | Remove NVM environment initialization and `nodejs_version` dependency, directly append `/opt/homebrew/bin` to PATH |

## TC-MAC-006: NPM Global Helper Script Installation Refused

| Item | Content |
|------|------|
| **Trigger File** | `roles/ai_agent_runtime/tasks/nodejs.yml` |
| **Trigger Error** | `chown failed: [Errno 1] Operation not permitted: '/usr/local/sbin/...'` |
| **Fix Solution** | Downgrade installation path to `~/.local/bin` under macOS, create directory beforehand, turn off `become` |

## TC-MAC-007: Playwright Hardcoded Associated Call Failure

| Item | Content |
|------|------|
| **Trigger File** | `roles/ai_agent_runtime/tasks/nodejs.yml` |
| **Trigger Error** | `[Errno 13] Permission denied: '/usr/local/sbin/ai-workspace-manage-npm-global-package'` |
| **Fix Solution** | Uniformly use conditional path statements in all `cmd` |

## TC-MAC-008: Apt Browser Installation Crash

| Item | Content |
|------|------|
| **Trigger File** | `roles/ai_agent_runtime/tasks/browser.yml` |
| **Trigger Error** | `[Errno 2] No such file or directory: b'update'` (macOS has no apt) |
| **Fix Solution** | Add `when: ansible_os_family != 'Darwin'`; supplement macOS Chrome detection path; change environment variable script path to user directory |

## TC-MAC-009: Playwright Environment Variable Mount Directory Missing

| Item | Content |
|------|------|
| **Trigger File** | `roles/ai_agent_runtime/tasks/browser.yml` |
| **Trigger Error** | `Destination directory ~/.local/state/ai-workspace/env does not exist` |
| **Fix Solution** | Pre-create the env directory; add `default(ansible_env.HOME)` to the variable for fault tolerance |

## TC-MAC-010: Agent Skills Role Hardcoded Path and User

| Item | Content |
|------|------|
| **Trigger File** | `roles/agent_skills/defaults/main.yml`, `roles/agent_skills/tasks/main.yml` |
| **Trigger Error** | `[Errno 45] Operation not supported: b'/home/ubuntu'` |
| **Fix Solution** | Change all defaults to `ansible_env.USER/HOME`; add Darwin skip to apt rsync installation |

## TC-MAC-011: Chromium Version Check Path Contains Spaces

| Item | Content |
|------|------|
| **Trigger File** | `roles/ai_agent_runtime/tasks/verify.yml` |
| **Trigger Error** | `No such file or directory: b'/Applications/Google'` (Path containing space is split) |
| **Fix Solution** | Change `ansible.builtin.command` to use `argv` list format parameter passing to avoid space truncation |

## TC-MAC-012: XWorkMate Bridge Base Directory System Path Write Denied

| Item | Content |
|------|------|
| **Trigger File** | `setup-ai-workspace-all-in-one.sh` → `roles/vhosts/xworkmate_bridge` (Variable `xworkmate_bridge_base_dir`) |
| **Trigger Error** | `TASK [roles/vhosts/xworkmate_bridge/ : Ensure xworkmate-bridge base directory exists]` → `There was an issue creating /opt/cloud-neutral as requested: [Errno 13] Permission denied: b'/opt/cloud-neutral'` |
| **Root Cause** | `xworkmate_bridge_base_dir` is hardcoded to `/opt/cloud-neutral/xworkmate-bridge` by default. macOS runs with `ansible_become=false`, has no permission to write to `/opt`; moreover, `/opt` is not a standard macOS directory. This base dir is simultaneously referenced by `config.yaml` and the launchd plist's `WorkingDirectory` |
| **Directory Strategy** | Linux maintains `/opt/cloud-neutral/xworkmate-bridge`; macOS switches to the Apple standard user-level application data directory `~/Library/Application Support/cloud-neutral/xworkmate-bridge` |
| **Fix Solution** | Two-layer: ① The Darwin branch of `setup-ai-workspace-all-in-one.sh` injects `-e xworkmate_bridge_base_dir="$HOME/Library/Application Support/cloud-neutral/xworkmate-bridge"` (`curl \| bash` pulls the script from this repo, playbooks come from an independent repo, so `-e` on the script side is the only effective fix point under this path); ② The role's `defaults/main.yml` changes the default value to a ternary expression based on `ansible_os_family`, making the offline/local playbook path also correct |
| **Effectiveness Prerequisite** | `curl \| bash` pulls the script from GitHub `main`. The fix must first be pushed to `main` of `ai-workspace-lab/xworkspace-console`; otherwise, the remote is still the old script (extra-vars have the highest priority, if `-e` was executed it would never fall back to `/opt`, thereby determining the unfixed remote script was executed) |

## TC-MAC-013: Vault standalone Directory System Path Write Denied

| Item | Content |
|------|------|
| **Trigger File** | `roles/vhosts/vault/tasks/main.yml`, `roles/vhosts/vault/vars/main.yml`, `roles/vhosts/vault/tasks/macos.yml` |
| **Trigger Error** | `TASK [roles/vhosts/vault/ : Ensure standalone Vault directories exist]` → `[Errno 13] Permission denied: b'/etc/vault.d'`, `b'/opt/vault'` |
| **Root Cause** | The "Ensure standalone Vault directories exist" task creates `/etc/vault.d` and `/opt/vault/data` with `owner: root`, and **lacks** the `ansible_os_family != 'Darwin'` guard that other standalone tasks in the vault role have. macOS runs with `become=false`, has no permission to write to `/etc`, `/opt`, and chown of `owner: root` cannot complete. Unlike bridge (whose directory owner is the service user, fixable by `-e`), the `owner: root` in this task is hardcoded, cannot be overridden by extra-vars, and the role logic must be changed |
| **Directory Strategy** | Linux maintains `/etc/vault.d`, `/opt/vault/data`; macOS switches to Apple standard `~/Library/Application Support/vault`, `~/Library/Application Support/vault/data`; macOS binary path takes `/opt/homebrew/bin/vault` (brew installation location), eliminating the need for `/usr/local/bin` symlinks that require sudo |
| **Fix Solution** | The role is located in an independent playbooks repo, cannot be directly committed from this repo; reuse the script's existing "post-clone patch" mechanism (see `patch_playbook_user_systemd`), add `patch_playbook_vault_macos()` to `setup-ai-workspace-all-in-one.sh`, and only apply to the cloned vault role under Darwin: ① Append `ansible_os_family != 'Darwin'` guard to the directory creation task; ② Change `vault_config_dir`/`vault_data_dir`/`vault_binary_path` to OS-based ternary expressions; ③ Pre-create user-owned data directories (including launchd log directory `~/.local/state/xworkspace`) in `macos.yml`. This patch is effective for both `curl \| bash` and local execution paths, is idempotent, and does not alter Linux behavior |

## TC-MAC-014: common Role Linux Baseline (timedatectl, etc.) Fails on macOS

| Item | Content |
|------|------|
| **Trigger File** | `roles/vhosts/common/tasks/main.yml` |
| **Trigger Error** | `TASK [common : Base | set timezone]` → `[Errno 2] No such file or directory: b'timedatectl'` (macOS lacks systemd's `timedatectl`) |
| **Root Cause** | The `Base | *` series of tasks in the `common` role are Linux server baselines: `timedatectl` to set timezone, rewriting `/etc/hostname`, `/etc/hosts`, setting hostname, SSH hardening, configuring fail2ban, adjusting file descriptor limits, allowing firewall ports. All are `become: true` and rely on Linux-specific tools/paths. On macOS (`become=false`), they will fail sequentially, with `set timezone` just being the first |
| **Fix Solution** | Evaluated that these baselines are neither applicable nor authorized for execution on local macOS development deployments. Therefore, `patch_playbook_common_macos()` is added to `setup-ai-workspace-all-in-one.sh` (also via post-clone patch) to append the `ansible_os_family != 'Darwin'` guard to the entire `Base | *` block only under Darwin (9 places total: 7 tasks appended `when`, 2 existing `when` lists appended this condition). The `when` on `import_tasks` propagates to subtasks, so ssh hardening/fail2ban/limits/firewall subtasks are skipped together. Idempotent, valid YAML, Linux behavior unchanged |
| **Note** | The user only explicitly mentioned `set timezone`, but the subsequent Base tasks would fail continuously for the same reason, so they were guarded together to avoid step-by-step round trips |

## TC-MAC-015: Vault Admin Initialization Script Lacks Dependencies/PATH on macOS

| Item | Content |
|------|------|
| **Trigger File** | `roles/vhosts/vault/tasks/main.yml` (Bootstrap task), `roles/vhosts/vault/files/init_vault_admin.sh`, `roles/vhosts/vault/tasks/macos.yml` |
| **Trigger Error** | `TASK [vault : Bootstrap Vault admin userpass auth]` failed (`no_log: true` hides details). Vault is already up at this point (health check passed), failure occurs during execution of `init_vault_admin.sh` |
| **Root Cause** | Script uses `require_cmd vault/jq/curl/base64`. macOS default **does not include jq**, and the "Install standalone Vault dependencies" (apt) task that installs jq is skipped by the `!= 'Darwin'` guard → jq is missing; simultaneously, `ansible.builtin.script` uses a minimal PATH that doesn't include Homebrew's `/opt/homebrew/bin`, so even `brew install`ed `vault`/`jq` might not be found |
| **Fix Solution** | Extend `patch_playbook_vault_macos()`: ① Add `brew install jq` (`creates: /opt/homebrew/bin/jq`) in `macos.yml`; ② Append `environment: PATH: "/opt/homebrew/bin:/usr/local/bin:{{ ansible_env.PATH }}"` to the Bootstrap task, ensuring the script can find brew-installed vault/jq. The script itself already has macOS adaptation (`base64 -D` detection). Patch is idempotent, valid YAML, Linux unchanged |
| **Note** | If it still fails, temporarily disable `no_log` on the task to view the real stderr of `init_vault_admin.sh` for further troubleshooting |

## TC-MAC-016: Vault Admin Initialization Non-Idempotent (re-run reports missing entityID)

| Item | Content |
|------|------|
| **Trigger File** | `roles/vhosts/vault/files/init_vault_admin.sh` |
| **Trigger Error** | `Error writing data to identity/mfa/method/totp/admin-generate ... Code: 400 ... * missing entityID`, accompanied by `A login request was issued that is subject to MFA validation` |
| **Root Cause** | The script attempts to get `entity_id` by "logging in as that user" (`auth/userpass/login/<user>`). However, the script then creates a login-MFA enforcement for userpass. The dev mode Vault runs persistently across multiple deployments (launchd daemon), so in the **second and subsequent** deployments, this login is intercepted by MFA. It returns an MFA pending validation response instead of a complete token, `entity_id` is empty → `admin-generate` reports `missing entityID`. This is a re-run idempotency defect, not specific to macOS (Linux will fall into the same trap on the second run) |
| **Fix Solution** | Stop relying on logins that will be intercepted by MFA: change to parsing `entity_id` via userpass identity **entity-alias** — iterate through `identity/entity-alias/id`, find the alias where name==user and mount_accessor==userpass accessor, and take its `canonical_id`; on the first run (no alias), explicitly create entity + entity-alias. Remove the `vault token revoke` which is subsequently no longer needed. Idempotent, backward compatible (can recognize implicitly created entities from older version logins). Fixed in the real playbooks repository `init_vault_admin.sh`; clone path synchronized via `patch_playbook_vault_macos()` |
| **Troubleshooting Method** | The `no_log: true` on this task hid the error; temporarily changed `no_log: false` + register + wrote stdout/stderr to a mounted directory file, read directly to obtain the true error |

## TC-MAC-017: PostgreSQL Misuses compose Mode on macOS

| Item | Content |
|------|------|
| **Trigger File** | `roles/vhosts/postgres/tasks/compose.yml`, `roles/vhosts/postgres/defaults/main.yml` |
| **Trigger Error** | `TASK [postgres : Materialize PostgreSQL admin password]` failed (`no_log: true`). assert `postgresql_admin_password | length > 0` evaluates to empty |
| **Root Cause** | `postgresql_deploy_mode` defaults to `compose`. compose.yml follows the Docker path (check/install apt version of docker), and `postgresql_admin_password` is generated by default via `lookup('password', '/root/.ai_workspace_postgres_password ...')` — macOS has no permission to write to `/root`, lookup fails → password is empty → assert fails. The role actually has a `native`+`macos.yml` (Homebrew postgresql@16) path prepared, but wasn't switched to by default on macOS |
| **Directory/Mode Strategy** | macOS deployment `postgresql_deploy_mode=native` (→ `macos.yml`, brew install); Linux deployment keeps default `compose` |
| **Fix Solution** | Inject `-e postgresql_deploy_mode=native` in the Darwin branch of `setup-ai-workspace-all-in-one.sh`, and provide the password directly with `append_secret_var postgresql_admin_password=$UNIFIED_AUTH_TOKEN` (extra-vars have highest priority, completely bypassing the `/root` password lookup). Linux branch remains unchanged |

## TC-MAC-018: postgres native Install Misuses Expired Intel Homebrew Crash

| Item | Content |
|------|------|
| **Trigger File** | `roles/vhosts/postgres/tasks/macos.yml` |
| **Trigger Error** | `Ensure PostgreSQL 16 is installed via Homebrew` → `/usr/local/Homebrew/.../macos_version.rb: unknown or unsupported macOS version: "27.0" (MacOSVersion::Error)` |
| **Root Cause** | This task uses the `community.general.homebrew` module. The module auto-detects the brew prefix and hit the **expired Intel Homebrew** (`/usr/local/Homebrew`) on the machine. Its built-in macOS version table does not recognize `27.0`, causing brew to crash on startup. Meanwhile, vault/openclaw using `command: brew` (which uses the available brew on PATH, like Apple Silicon's `/opt/homebrew`) worked fine—this is the module selecting the wrong brew, not brew being entirely unavailable |
| **Fix Solution** | Align with vault/openclaw: change to `ansible.builtin.command: brew install postgresql@16`, and prepend `/opt/homebrew/bin:/usr/local/bin` to `environment.PATH` (prioritizing the available brew), add `HOMEBREW_NO_AUTO_UPDATE=1`; maintain idempotency using `register`+`changed_when`/`failed_when`. Real repository `macos.yml` is updated; clone path synchronized via `patch_playbook_postgres_macos()` |
| **Note** | If the machine only has a single, expired brew (pure Intel), the root cause is the environment, requiring `brew update`/reinstalling Homebrew; this fix bypasses the issue as long as an "available brew exists" (the vault step proved an available brew exists) |

## TC-MAC-019: litellm Similarly Misuses Homebrew Module Crash

| Item | Content |
|------|------|
| **Trigger File** | `roles/vhosts/litellm/tasks/main.yml` |
| **Trigger Error** | `Install LiteLLM prerequisites (macOS)` → `/usr/local/Homebrew/.../macos_version.rb: unknown or unsupported macOS version: "27.0"` |
| **Root Cause** | Same root as TC-MAC-018: `community.general.homebrew` module hits expired Intel Homebrew and crashes |
| **Fix Solution** | Change to `ansible.builtin.command: brew install python@3.13` + prepend `/opt/homebrew/bin:/usr/local/bin` to `environment.PATH` + `HOMEBREW_NO_AUTO_UPDATE=1`. Real repository updated; clone path synchronized via `patch_playbook_litellm_macos()` |
| **Note** | litellm still has macOS gaps to be handled individually subsequently: `/root` derived salt/db secret asserts, `/etc/litellm` config directory, pip/prisma tasks using `become: true` + `become_user` (service user is not created on macOS), DB provisioning, etc. |

## Current Progress Snapshot (2026-06-22)

The current macOS debugging entry point remains the public installation command:

```bash
curl -sfL https://install.svc.plus/ai-workspace | bash -
```

As of 2026-06-22, the `xworkspace-console` bootstrap entry, `playbooks` all-in-one role pipeline, and `ai-workspace-services/litellm` runtime release pipeline have formed a three-repository coordination. The macOS local deployment has bypassed early path, permission, Homebrew, Vault, PostgreSQL, OpenClaw, QMD and other blocking points. Current remaining risks mainly focus on the network stability of LiteLLM dependency installation, the product verification of the offline runtime release, and the final consecutive idempotent deployments.

Key commits pushed to `ai-workspace-infra/playbooks`:

| Commit | Theme | Impact on macOS Deployment |
|---|---|---|
| `09a39e6` | `perf(openclaw): avoid unnecessary doctor repairs` | Separates OpenClaw doctor and restart, preventing normal restart from triggering `doctor --fix --force` |
| `f01e0bb` | `fix(qmd): provision macOS LaunchAgent` | Supplements user-level LaunchAgent for QMD, supporting starting MCP service on macOS |
| `c11f51b` | `fix(openclaw): allow version-matched acpx plugin` | Supports version-matched `acpx` plugin, avoiding accidental kill by plugin registry assert |
| `71ebe64` | `fix(litellm): isolate runtime in Python 3.13 venv` | LiteLLM changed to Python 3.13 venv isolation, avoiding mixing Python 3.13/3.14 |
| `6a2f05f` | `fix(litellm): skip redundant dependency installs` | Adds package detection and install markers, skipping installed LiteLLM dependencies during repeated execution |

Key commits pushed to `ai-workspace-services/litellm`:

| Commit | Theme | Impact on macOS/Offline Deployment |
|---|---|---|
| `51cde5e32` | `ci: add offline litellm runtime workflow` | Adds `.github/workflows/offline-package-litellm-runtime.yaml`, outputting `litellm-runtime-<distro>-<version>-<arch>.tar.gz` for console offline package scripts |

Still need to use a clean install to verify if the remote script pointed to by `install.svc.plus` already contains the latest bootstrap logic. If the failure point still shows old tasks or old paths, first confirm whether the release entry point has been synchronized to the latest version of `ai-workspace-lab/xworkspace-console@main`.

## TC-MAC-020: OpenClaw doctor is Too Heavy Causing Slow Handler

| Item | Content |
|------|------|
| **Trigger File** | `roles/vhosts/gateway_openclaw/handlers/main.yml` |
| **Trigger Phenomenon** | `RUNNING HANDLER [roles/vhosts/gateway_openclaw/ : Repair OpenClaw health findings (POSIX)]` takes about 5-6 seconds; previously restart and doctor were bound, normal config changes could also trigger `openclaw doctor --fix --force --yes` |
| **Root Cause** | The handler coupled "lightweight restart" and "doctor repair", and `--fix --force` runs the repair path by default, suitable for real health issues, not suitable to run on every deployment conclusion |
| **Fix Solution** | Doctor and restart have been split in `playbooks`: normally only do lightweight restart; trigger doctor only on actual package/config/plugin changes; prioritize lighter check/repair mode, reducing unrelated changes pulling up doctor |
| **Verification Status** | Committed `09a39e6`. Still need to observe if the OpenClaw handler is only triggered on real changes in a complete macOS deployment |

## TC-MAC-021: QMD Lacks macOS LaunchAgent

| Item | Content |
|------|------|
| **Trigger File** | `roles/vhosts/qmd/` |
| **Trigger Phenomenon** | QMD MCP port `http://localhost:8181/mcp` needs to run as a macOS user service, but the role lacks launchd provisioning |
| **Root Cause** | The Linux/systemd path already has service management, macOS lacks user-level service descriptions like `LaunchAgents/plus.svc.xworkspace.qmd.plist` |
| **Fix Solution** | Add QMD LaunchAgent: `plus.svc.xworkspace.qmd`, starting it as a macOS user-level service |
| **Verification Status** | Committed `f01e0bb`. Still need to verify `launchctl` status and `http://localhost:8181/mcp` reachability after complete install |

## TC-MAC-022: OpenClaw Codex Plugin Compatibility Assert Accidental Kill

| Item | Content |
|------|------|
| **Trigger File** | `roles/vhosts/gateway_openclaw/tasks/main.yml` |
| **Trigger Error** | `Assert OpenClaw Codex plugin matches gateway version` fails, prompting that it must run `@openclaw/codex 2026.6.1` and `openclaw-multi-session-plugins 2026.6.1`, and must not retain stale global `@openclaw/acpx` |
| **Root Cause** | After OpenClaw was upgraded to `2026.6.1`, the OpenClaw-managed `@openclaw/acpx` remained at `2026.5.28`. The role only checked the version at the end and did not repair plugin version drift |
| **Fix Solution** | Inspect ACPX before refreshing the registry; install the exact `@openclaw/acpx@2026.6.1` package when missing, or run `openclaw plugins update acpx` when stale, then enforce the version assertion |
| **Verification Status** | ACPX was upgraded from `2026.5.28` to `2026.6.1` on the Linux target and a full deployment was rerun; the same path still needs verification during a complete macOS installation |

## TC-MAC-023: LiteLLM Python 3.13/3.14 Mixed Use

| Item | Content |
|------|------|
| **Trigger File** | `roles/vhosts/litellm/defaults/main.yml`, `roles/vhosts/litellm/tasks/main.yml` |
| **Trigger Phenomenon** | On macOS, Homebrew Python mixes with system/other Python versions. LiteLLM dependencies might be installed into inconsistent interpreters or site-packages, causing instability in `prisma generate` and service startup |
| **Root Cause** | Early installation paths didn't enforce independent venvs, and the macOS environment might simultaneously possess Python 3.13 and 3.14 |
| **Fix Solution** | LiteLLM runtime fixed to use Python 3.13 to create an isolated venv: `~/.local/share/litellm/venv`; `pip`, `litellm`, and `prisma` are all executed from this venv |
| **Verification Status** | Committed `71ebe64`. Still need a full deployment to verify service startup and `prisma generate` |

## TC-MAC-024: LiteLLM Dependency Install is Slow and Public Network Download Easily Interrupts

| Item | Content |
|------|------|
| **Trigger File** | `roles/vhosts/litellm/tasks/main.yml`, `roles/vhosts/litellm/defaults/main.yml` |
| **Trigger Error** | `Ensure LiteLLM and DB dependencies are installed` took up to ~581 seconds, then failed due to download interruptions from GitHub archive or PyPI wheel like `IncompleteRead` / `curl 18` / EOF |
| **Root Cause** | The `litellm[proxy]` dependency tree is large, containing huge packages like `polars-runtime-32`, `cryptography`, `boto3`, `mcp`. Direct online `pip install` is both slow and relies on network stability. Changing `git+https` to GitHub archive solved git clone EOF, but large wheel download interruptions are still unavoidable |
| **Fixed** | ① Default install source changed from `git+https` to GitHub archive; ② Added `PIP_CACHE_DIR` and longer timeout; ③ Probe for installed `litellm/prisma/psycopg2-binary` before install, and skip duplicate installs using `.install-spec` marker; ④ Added offline runtime workflow to `ai-workspace-services/litellm` to pre-build target distribution wheelhouses |
| **Current Status** | Online install path has mitigated but not eradicated network risks; the true long-term solution is to have all-in-one prioritize consuming the wheelhouse within `litellm-runtime-<distro>-<version>-<arch>.tar.gz` |
| **To Verify** | Need to trigger and confirm `offline-package-litellm-runtime.yaml` generates a release in GitHub Actions, and `xworkspace-console/scripts/create-ai-workspace-offline-package.sh` can pull the matching runtime asset from `ai-workspace-services/litellm` |

## TC-MAC-025: LiteLLM runtime release Connection with all-in-one Offline Package

| Item | Content |
|------|------|
| **Trigger File** | `ai-workspace-services/litellm/.github/workflows/offline-package-litellm-runtime.yaml`, `xworkspace-console/scripts/create-ai-workspace-offline-package.sh`, `xworkspace-console/scripts/ai-workspace-offline-install.sh` |
| **Contract** | The console offline package script will download `litellm-runtime-${DISTRO_ID}-${DISTRO_VERSION}-${ARCH}.tar.gz` under `LITELLM_RUNTIME_RELEASE_REPO=ai-workspace-services/litellm`, extract it, and copy `packages/pip`, optionally `packages/python`, and `metadata/runtime.env` |
| **Completed** | Added workflow to `litellm` repo, with matrix covering Debian 11/12/13 and Ubuntu 22.04/24.04/26.04 on amd64/arm64; Ubuntu 26.04 additionally packages portable Python 3.13.14; SHA256SUMS merged in release |
| **To Do** | Need to verify if GitHub Actions actual runs succeed; need to confirm release tag naming matches console side `latest-runtime` resolution; need to practically test if `metadata/litellm-runtime.env` correctly injects `LITELLM_PACKAGE_SPEC` in the offline all-in-one package |

## TC-MAC-026: uninstall purge Needs to Print Deleted Paths

| Item | Content |
|------|------|
| **Trigger Command** | `curl -sfL https://install.svc.plus/ai-workspace \| bash -s -- uninstall purge` |
| **Requirement** | The purge mode not only deletes local state but should also explicitly print paths to be/already deleted, facilitating user confirmation of the cleanup scope |
| **Current Status** | Identified as a to-do item; need to extract a unified `purge_path` / `purge_matching_paths` helper in the uninstall/purge branch of `setup-ai-workspace-all-in-one.sh`, outputting existing paths before deletion, and also outputting skipped/absent when not existing |
| **Involved Paths** | macOS includes at least `~/.ai_workspace_auth_token`, `~/.vault_password`, `~/.openclaw`, `/tmp/xworkspace-core-skills`, `/tmp/xworkmate-bridge`, `/tmp/ai-workspace-deploy`; Linux additionally includes `/opt/ai-workspace`, `/etc/ai-workspace`, user systemd units, etc. |

## TC-MAC-027: Non-Source Code Formal Directory Cleanup

| Item | Content |
|------|------|
| **Trigger Phenomenon** | Generated directories like `ai-workspace-all-in-one-offline-ubuntu-22.04-amd64/` appear in the workspace |
| **Root Cause** | Offline package build/extraction products entered the development workspace, easily mistaken for source code directories |
| **Handling Principle** | Generated products that don't belong to the formal directories of the source repository should be cleaned up from the workspace; offline package output should be placed in explicit `dist/`, release artifact, or temp directories, and shouldn't mix into the source root |
| **To Do** | Need to append a repo-level sweep subsequently: confirm `git status --ignored` for `xworkspace-console`, `playbooks`, and `litellm` respectively, clean untracked offline package directories, and append `.gitignore` as needed |

## TC-MAC-028: LiteLLM Dependency Version Detection One-Line Python Syntax Error Causes set_fact Crash

| Item | Content |
|------|------|
| **Trigger File** | `roles/vhosts/litellm/tasks/main.yml` (Inspect/Decide task) |
| **Trigger Error** | `TASK [litellm : Decide whether LiteLLM dependencies need installation]` → `the field 'args' ... could not be converted to dict.. Expecting value: line 1 column 1 (char 0)` |
| **Root Cause** | The "Inspect installed LiteLLM dependency versions" detection script was written as multi-line Python, but under YAML `>-` folding, all newlines were compressed into spaces, turning `for package in packages: try: ... except:` into an illegal single line → SyntaxError. `failed_when: false` swallowed the failure causing empty stdout, and subsequently `set_fact`'s `from_json('')` crashed. `default('{}')` does not replace empty strings (only undefined) |
| **Fix Solution** | Changed detection to a true one-liner program (using dict/list comprehensions for `importlib.metadata.distributions()`, connected by semicolons); decision `set_fact` uses `default('{}', true)`, meaning empty/illegal output degrades to "installation needed" instead of aborting the playbook. Commit `ce2070e` |

## TC-MAC-029: prisma generate Cannot Find prisma-client-py Generator

| Item | Content |
|------|------|
| **Trigger File** | `roles/vhosts/litellm/tasks/main.yml` (Generate Prisma Python Client) |
| **Trigger Error** | `Error: Generator "prisma-client-py" failed: /bin/sh: prisma-client-py: command not found` |
| **Root Cause** | `prisma generate` invokes the `prisma-client-py` generator as a `/bin/sh` subprocess, its console script is installed in the venv's bin directory. However, the task called prisma with an absolute path but didn't put the venv bin into PATH, so the default command PATH couldn't resolve the generator |
| **Fix Solution** | Added `environment.PATH` to this task, prepending `{{ litellm_venv_dir }}/bin` (then Homebrew prefix), making the generator subprocess resolvable. Commit `bbf5260` |

## TC-MAC-030: QMD LaunchAgent References Undefined nodejs_version

| Item | Content |
|------|------|
| **Trigger File** | `roles/vhosts/qmd/templates/qmd.plist.j2` |
| **Trigger Error** | `TASK [qmd : Deploy QMD LaunchAgent]` → `AnsibleUndefinedVariable: 'nodejs_version' is undefined` |
| **Root Cause** | The plist's PATH hardcoded `~/.nvm/versions/node/{{ nodejs_version }}/bin`, but under Homebrew deployment, `nodejs_version` was never defined (same anti-pattern as TC-MAC-005) |
| **Fix Solution** | QMD is a bun binary, and the Linux user unit already uses `.bun/bin:.local/bin:...`; plist PATH aligned to `{{ qmd_home }}/.bun/bin:{{ qmd_home }}/.local/bin:/opt/homebrew/bin:...`, removing nvm/nodejs_version dependencies. Commit `d903396` |

## TC-MAC-031: QMD better-sqlite3 Native Module Node ABI Mismatch

| Item | Content |
|------|------|
| **Trigger File** | `roles/vhosts/qmd/tasks/main.yml` (npm install / npm run build / Validate QMD status) |
| **Trigger Error** | `TASK [qmd : Validate QMD status]` → `Error: ... better_sqlite3.node was compiled against a different Node.js version using NODE_MODULE_VERSION 137. This version of Node.js requires NODE_MODULE_VERSION 115` (`ERR_DLOPEN_FAILED`) |
| **Root Cause** | better-sqlite3 was compiled with node@24 (ABI 137), but the validate-status task didn't fix PATH. The user PATH's nvm Node 20 (ABI 115) ranked before Homebrew, causing inconsistent Node ABI between runtime and build |
| **Fix Solution** | The three tasks (npm install / npm run build / validate-status) under Darwin use `{{ '/opt/homebrew/bin:/usr/local/bin:' if ansible_os_family == 'Darwin' else '' }}{{ ansible_env.PATH }}` to fix node@24, ensuring build and runtime ABI consistency (consistent with plist); Linux PATH unchanged. Commit `6091b9d` |

## TC-MAC-032: XFCE/XRDP Linux Desktop Stack Fails to run apt on macOS

| Item | Content |
|------|------|
| **Trigger File** | `setup-xfce-xrdp.yaml` → `roles/vhosts/xfce_desktop_minimal_runtime` |
| **Trigger Error** | `TASK [xfce_desktop_minimal_runtime : Update apt cache]` → `[Errno 2] No such file or directory: b'update'` (macOS lacks apt) |
| **Root Cause** | XFCE + XRDP is a Linux remote desktop stack (apt/systemd), which is meaningless on macOS that already has a native GUI, but all-in-one still ran this play down to Darwin |
| **Fix Solution** | Both `include_role`s in `setup-xfce-xrdp.yaml` gained `when: ansible_os_family != 'Darwin'`, skipping the entire stack on macOS; Linux unchanged. Commit `ef67c61` |

## TC-MAC-033: LiteLLM DATABASE_URL Password Not Percent-Encoded Causes Prisma P1013

| Item | Content |
|------|------|
| **Trigger File** | `roles/vhosts/litellm/defaults/main.yml` (`litellm_database_url`) |
| **Trigger Phenomenon** | Deployment "succeeds" (ansible `failed=0`) but service summary shows `LiteLLM : inactive (not detected;http:000)`, launchd exit code non-0, port 4000 not listening; `litellm.err.log` repeats `Error: P1013: The provided database string is invalid. invalid port number in database URL` |
| **Root Cause** | Unified auth token generated via `openssl rand -base64` may contain `/`, `+`, `=`; when directly concatenated into userinfo of `postgresql://litellm:<token>@host:port/db`, `/` truncates the URL authority, failing port parsing, proxy fails to start, 4000 not listening. Health check `failed_when: false` masked it, ansible still reported success |
| **Fix Solution** | Percent-encode only the password in DATABASE_URL (added `litellm_database_password_urlencoded`, explicit replace chain prioritizing `%`; Jinja `urlencode` doesn't escape `/` so it's unusable). The actual DB user password in provision-database and `LITELLM_DB_PASSWORD` keeps original text, URL format decoded matches original (round-trip verified), auth remains unchanged. Commit `9926a46` |
| **Verification Method** | ansible `failed=0` ≠ service available: need independent confirmation via `launchctl list` (Status 0), `lsof -iTCP:4000 -sTCP:LISTEN`, `curl /health` (**401 means healthy**, auth-gated) |

---

## Fix Dimension Summary

| Dimension | Involved Cases |
|------|---------|
| Component acquisition method replacement (brew vs binary) | TC-001 |
| Privilege reduction (become: false) | TC-002, TC-006, TC-007, TC-008, TC-009 |
| User group adaptation (staff vs ubuntu) | TC-003, TC-010 |
| Directory path downgrade ($HOME vs /home/ubuntu, /opt, /etc) | TC-004, TC-006, TC-009, TC-010, TC-012, TC-013 |
| Post-clone patch injection | TC-013, TC-014 |
| Linux baseline total skip (skip Linux baseline on Darwin) | TC-014, TC-032 |
| brew dep supplement + PATH injection (jq via brew, Homebrew on PATH) | TC-015 |
| Package manager bypass (skip apt on Darwin) | TC-008, TC-010, TC-032 |
| Template variable decoupling (remove nvm/nodejs_version) | TC-005, TC-030 |
| Path space compatibility (argv vs string) | TC-011 |
| Homebrew module bypass (command brew + PATH) | TC-018, TC-019 |
| venv/Node subprocess PATH injection (resolve generator/native ABI) | TC-029, TC-031 |
| Node ABI consistency (build == runtime node@24) | TC-031 |
| macOS launchd user service | TC-021 |
| handler trigger condition convergence | TC-020 |
| Python venv isolation and pip cache | TC-023, TC-024 |
| One-line template/folding syntax robustness (`>-` folding, default(.,true)) | TC-028 |
| Connection string password percent encoding (URL-encode secrets) | TC-033 |
| Offline runtime wheelhouse | TC-025 |
| purge observability | TC-026 |
