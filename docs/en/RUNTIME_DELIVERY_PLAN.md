[🇺🇸 English](../../README.md) | [🇨🇳 中文](../../README.zh.md)

# AI Workspace Runtime Delivery Plan

> Goal: Converge `setup-ai-workspace-all-in-one.sh` from "a set of scattered infrastructure Playbooks" into a **ready-to-use AI Workspace Runtime product**—version controlled, composable run modes, exposing only the Bridge externally, and outputting a one-time unified summary upon deployment completion.
>
> This document is the detailed plan before implementation (design + change list + commit/deploy/acceptance scheme). During the implementation phase, follow this document strictly, do not expand the scope of modification, do not do large-scale refactoring, and prioritize reusing existing implementations.

- Status: The Linux offline package pipeline and macOS local verification pipeline have entered the joint debugging phase; macOS has overcome most role compatibility blockers, the current focus is LiteLLM offline runtime integration, full installation rerun, and idempotent acceptance.
- Impacted repositories: `ai-workspace-infra/playbooks`, `ai-workspace-lab/xworkspace-console`, `ai-workspace-lab/xworkspace-core-skills`, `ai-workspace-services/qmd`, `ai-workspace-services/litellm`
- Target host: `root@acp-bridge.onwalk.net`
- Default external domain (only public service): `acp-bridge.onwalk.net`

## TODO

- [x] Wait and check the offline package GitHub Actions release pipeline of `xworkspace-console`, confirm `publish-release` completes fully and release artifacts upload successfully.
- [ ] Continue to check the remote deployment progress of `root@acp-bridge.onwalk.net`, confirm `setup-ai-workspace-all-in-one.sh` finally completes and outputs the unified summary.
- [x] `setup-ai-workspace-all-in-one.sh` preferentially uses offline installation packages on the target host to accelerate deployment, reducing online pull and installation time.
- [x] Add a runtime wheelhouse release workflow for LiteLLM, for all-in-one offline package consumption.
- [ ] Verify that the `ai-workspace-services/litellm` runtime release actually generates successfully, and confirm the console offline package can download the matching `litellm-runtime-<distro>-<version>-<arch>.tar.gz`.
- [ ] Verify the idempotency of `setup-ai-workspace-all-in-one.sh`: executing twice consecutively on the same host both succeed, reusing credentials, offline package cache and imported images, and safely waiting for deployment/APT locks.
- [ ] Complete macOS local final acceptance check: Portal, Bridge, OpenClaw, QMD, Hermes, PostgreSQL, Vault, LiteLLM statuses are normal, `http://localhost:8181/mcp` and LiteLLM health are reachable.
- [ ] Complete remote Linux final acceptance check: Bridge is externally reachable, other services only listen locally by default, `acp-codex` / `opencode` / `gemini` / `hermes` / `qmd` / `litellm` statuses are normal.
- [ ] Record the final commit hash, GitHub Actions run, release tag and remote verification results, backfill into the delivery results section of this plan.

---

## 6. Repository and Commit Plan

| Repository | Main Changes | Commit message (suggested) | Push Target |
|---|---|---|---|
| `playbooks` | Role split, version pinning, Bridge domain, run-mode guard, PG compose, QMD/LiteLLM source, aggregation chain deduplication, this plan document | `feat: deliver versioned AI Workspace Runtime (role split, run-mode matrix, bridge domain)` | `ai-workspace-infra/playbooks` |
| `xworkspace-console` | `setup-ai-workspace-all-in-one.sh` unified summary, pull source alignment, console not public by default | `feat: unified one-time deploy summary + bridge-only public surface` | `ai-workspace-lab/xworkspace-console` |
| `xworkspace-core-skills` | (On demand) skills seed/version alignment | `chore: align skills seed for workspace runtime` | `ai-workspace-lab/xworkspace-core-skills` |

> Submit **independently** for each repository, record the Commit Hash separately and write into the final delivery description.

### 6.1 Current Implementation Progress (2026-06-22)

| Repository | Completed Progress | Known Pending Issues |
|---|---|---|
| `ai-workspace-infra/playbooks` | OpenClaw doctor/restart split; QMD macOS LaunchAgent added; OpenClaw `acpx` compatibility assert fixed; LiteLLM switched to Python 3.13 venv, installation detection and `.install-spec` skip redundant installation | Full macOS rerun needed to confirm `qmd :8181/mcp`, OpenClaw registry, LiteLLM health; need to confirm all-in-one macOS patch and playbooks main no longer overwrite each other |
| `ai-workspace-lab/xworkspace-console` | all-in-one offline package pipeline can now consume console/bridge/qmd/litellm runtime releases; macOS debugging cases continuously recorded in `docs/case/macos_compatibility_tests.md` | `uninstall purge` still needs to print deleted paths; need to clean offline package generation directories and other non-source official directories; need to confirm `install.svc.plus/ai-workspace` publish entry syncs to latest main |
| `ai-workspace-services/qmd` | all-in-one offline package script consumes release as `qmd-runtime-linux-${ARCH}.tar.gz`; playbooks added QMD macOS LaunchAgent | Need to confirm latest runtime release and offline package pull path remain available; macOS needs to actually test MCP endpoint |
| `ai-workspace-services/litellm` | Added `.github/workflows/offline-package-litellm-runtime.yaml`, yielding `litellm-runtime-<distro>-<version>-<arch>.tar.gz`, wheelhouse, optional portable Python, `metadata/runtime.env` | Need to trigger GitHub Actions and confirm release asset and `SHA256SUMS`; need to confirm console offline package resolves this release using `latest-runtime` |
| `ai-workspace-lab/xworkspace-core-skills` | all-in-one offline package still packages by core-skills repo/ref | Currently no new macOS blockers found; final acceptance still needs to confirm skill injection and OpenClaw/QMD visibility |

### 6.2 Recent Key Commits

| Repository | Commit | Description |
|---|---|---|
| `ai-workspace-infra/playbooks` | `09a39e6` | `perf(openclaw): avoid unnecessary doctor repairs` |
| `ai-workspace-infra/playbooks` | `f01e0bb` | `fix(qmd): provision macOS LaunchAgent` |
| `ai-workspace-infra/playbooks` | `c11f51b` | `fix(openclaw): allow version-matched acpx plugin` |
| `ai-workspace-infra/playbooks` | `71ebe64` | `fix(litellm): isolate runtime in Python 3.13 venv` |
| `ai-workspace-infra/playbooks` | `6a2f05f` | `fix(litellm): skip redundant dependency installs` |
| `ai-workspace-services/litellm` | `51cde5e32` | `ci: add offline litellm runtime workflow` |

### 6.3 Issues Most Needing Closure Currently

1. `LiteLLM`: Online `pip install litellm[proxy]` may still fail due to large wheel download interruptions; the runtime wheelhouse release should be used as the default acceleration path for all-in-one, retaining the online path as fallback.
2. `install.svc.plus/ai-workspace`: Need to confirm the public shortlink actually pulls the latest script from `xworkspace-console@main`, otherwise macOS may still run old bootstrap.
3. `uninstall purge`: Need to output the paths to be deleted/deleted/non-existent, covering macOS and Linux tokens, Vault/OpenClaw states, temporary deployment directories, system configuration directories.
4. Workspace cleanup: Need to clean generated directories like `ai-workspace-all-in-one-offline-*` to prevent offline package artifacts from mixing into the source root directory.
5. Final acceptance: Need to do one clean installation and one repeat installation on macOS, recording each service port, LaunchAgent/systemd status, health endpoint and changed statistics.

---

## 8. Risks and Rollbacks

| Risk | Mitigation / Rollback |
|---|---|
| Sandbox cannot connect directly to GitHub/target host | Complete code+commits locally; push and remote deployment executed from an environment with network |
| PG switching to compose affects existing data | Retain `postgresql_deploy_mode=native` rollback path |
| Role split regression | `setup-xfce-xrdp.yaml` combines both roles, behavior is equivalent; retain old roles until reference switch passes validation |
| Version pinning causes pull failure | Version variables are centralized, can be overridden at a single point (env / `-e`) |

---

## 9. Implementation Sequence (Delivery Order)

1. Check in this plan document (`docs/`).
2. Role split + `setup-xfce-xrdp.yaml` combination.
3. Version pinning (OpenClaw/Vault/Hermes/QMD/LiteLLM/Node/Playwright/Chrome).
4. Bridge domain parameter pass-through (`XWORKMATE_BRIDGE_DOMAIN`, custom, does not change role default).
5. Run-mode guard + PG compose default.
6. Aggregation chain deduplication (Hermes) + console not public by default.
7. `setup-ai-workspace-all-in-one.sh` unified summary.
8. Commit separately for the three repositories, record Commit Hashes.
9. Push + remote deployment + verify according to §7.2.
10. Concurrency optimization delivery (see §10), finally do §10.8 equivalence regression.

---
