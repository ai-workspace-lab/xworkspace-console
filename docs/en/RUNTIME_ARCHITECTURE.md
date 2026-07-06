[🇺🇸 English](../../README.md) | [🇨🇳 中文](../../README.zh.md)

## 3. Current Situation Analysis: Role Hierarchy

`setup-ai-workspace-all-in-one.sh` (located in the console repository) runs `setup-ai-workspace-all-in-one.yml` (located in the playbooks repository) after bootstrapping on the target host. Its role hierarchy in import order is as follows:

```
setup-ai-workspace-all-in-one.sh            [repo: xworkspace-console/scripts]
  └─ ansible-playbook setup-ai-workspace-all-in-one.yml   [repo: playbooks]
     ├─1 setup-nodejs.yml          → role roles/vhosts/nodejs        NodeJS(22.x)+yarn
     ├─2 setup-xworkspace-console.yaml   WORKSPACE PORTAL/CONSOLE (inline task, no role)
     │      apt: caddy,xfce4,python3,golang-go,google-chrome-stable,ttyd
     │      git clone console → npm build; systemd --user: console(:17000)/api(:8788)/ttyd(:7681)/status.timer
     │      Caddy public site workspace.svc.plus   ⚠ also public in standard mode
     ├─3 setup-ai-agent-skills.yml → role roles/ai_agent_runtime    AI WORKSPACE RUNTIME Core
     │      NodeJS(24.x)+Playwright; Agent CLI: opencode/gemini/codex/claude; Python/browser/docs/fonts
     │      └─ role agent_skills → inject xworkspace-core-skills market skills
     ├─4 deploy_gateway_openclaw.yml → role roles/vhosts/gateway_openclaw   OpenClaw(2026.5.28)
     ├─5 deploy_xworkmate_bridge_vhosts.yml   BRIDGE + ACP Cluster
     │      ├─ import setup-xworkspace-console.yaml (run again with bridge variables)
     │      └─ roles: acp_server_codex / acp_server_opencode / acp_server_gemini /
     │               acp_server_hermes / xworkmate_bridge(:8787 local, public Caddy)
     │               domain defaults to xworkmate-bridge.svc.plus → acp-bridge.onwalk.net
     ├─6 setup-vault.yaml          → role roles/vhosts/vault        Vault(1.20.4) :8200
     ├─7 setup-postgres-standalone.yaml → role roles/vhosts/postgres(dep: common)  native apt PG17 :5432
     ├─8 setup-litellm.yaml        → role roles/vhosts/litellm      pip install :4000
     ├─9 deploy_QMD.yml            → role roles/vhosts/qmd          bun qmd, MCP :8181
     ├─10 deploy_agent_hermes.yml  → role roles/vhosts/acp_server_hermes   ⚠ Hermes duplicate deployment (overlaps with step 5)
     └─11 setup-xfce-xrdp.yaml [Optional] → role roles/vhosts/xfce_xrdp_minimal
            → Split into xfce_desktop_minimal_runtime + remote_desktop_xrdp_server
```

### 3.1 Key Findings

1. **Public Surface Conflict**: Steps 2/5 deploy the public Caddy site for `workspace.svc.plus` when `ai_workspace_security_level != strict`, causing the Portal to also be exposed externally, which conflicts with "Bridge as the only public service".
2. **Hermes Duplicate Deployment**: Step 5 (within the ACP cluster) and Step 10 (independent) each deploy it once, causing redundancy.
3. **Scattered Version Pinning**: OpenClaw and Vault have fixed variables; NodeJS has them but is too loose (`22.x`/`24.x`); Hermes, QMD, and LiteLLM lack explicit version/source pinning.

---

## 4. Key Design Decisions

### 4.1 Public Surface: Bridge Only

- **Bridge is the default and only public service**: `XWORKMATE_BRIDGE_PUBLIC_ACCESS` defaults to `true`, and the public domain is passed customly via `XWORKMATE_BRIDGE_DOMAIN` (target host `acp-bridge.onwalk.net`). To disable this, explicitly set it to `false`.
- `xworkspace_console_public_access` defaults to `false` (only public when `XWORKSPACE_CONSOLE_PUBLIC_ACCESS=true`).
- `GATEWAY_OPENCLAW_PUBLIC_ACCESS` / `VAULT_PUBLIC_ACCESS` default to `false`; the rest (QMD / Hermes / PG / LiteLLM) maintain local listening (`127.0.0.1`) and do not deploy public Caddy sites.
- Implementation approach: **Minimal changes** — only adjust default values/switches and align env names (§2.1), without removing the existing public_access capability (keep the manual override available).

### 4.2 Hermes Deduplication

- Remove the independent `deploy_agent_hermes.yml` import of Step 10 in `setup-ai-workspace-all-in-one.yml` (the ACP cluster in Step 5 already includes hermes).
- Keep the `deploy_agent_hermes.yml` file itself for standalone deployment scenarios, only deduplicating it from the all-in-one aggregation chain.

### 4.3 Runtime Mode Matrix (docker / k3s / systemd)

Introduce a **validation** variable `ai_workspace_runtime_modes` (list), and add an `assert` guard at the top of the all-in-one without rewriting the deployment logic of each component:

| Constraint | Rule |
|---|---|
| Mutually Exclusive | `docker` and `k3s` cannot be present at the same time |
| Composable | `docker + systemd` is allowed; `systemd` can be standalone |
| Default | `['docker','systemd']` (most Agent services use systemd, PostgreSQL uses docker compose) |

Component to mode mapping (reusing existing capabilities, no heavy new implementations):

| Component | systemd | docker | k3s |
|---|---|---|---|
| Console / API / ttyd / Bridge / ACP / OpenClaw / QMD / LiteLLM | ✅ Default | — | — |
| PostgreSQL | Optional | ✅ **Default docker compose** | Optional |
| Vault | `vault_deploy_mode=systemd` | — | `vault_deploy_mode=kubernetes` (k3s) |

Guard pseudo-code (place in the top-level play of all-in-one):

```yaml
- name: Validate runtime mode combination
  hosts: all
  gather_facts: false
  tasks:
    - assert:
        that:
          - not ('docker' in ai_workspace_runtime_modes and 'k3s' in ai_workspace_runtime_modes)
          - ai_workspace_runtime_modes | length > 0
        fail_msg: "docker and k3s are mutually exclusive; please select a valid combination of docker/k3s/systemd."
```

### 4.4 PostgreSQL Deployment Mode Support

- Add switch `postgresql_deploy_mode`, defaulting to `compose`. Three modes are supported:
  - `compose` mode: Run docker compose in `roles/vhosts/postgres` to deploy a local container.
  - `native` mode: Use native apt / systemd on Linux, and Homebrew postgresql@16 on macOS.
  - `external` mode: Use an existing external database service, skipping the local installation and startup of PostgreSQL.
- Support specifying the external database connection via `POSTGRESQL_DATABASE_URL` (format: `postgres://user:password@host:port/database?options`). The setup script will automatically parse this and inject its components into the deployment environment.
- Do not remove the native apt path (can fallback by setting `postgresql_deploy_mode=native`).

### 4.5 QMD / LiteLLM Source Repo and Version Pinning

- QMD: Installation source points to `https://github.com/ai-workspace-services/qmd.git`, adding `qmd_source_repo` / `qmd_version` variables for pinning.
- LiteLLM: Installation source points to `https://github.com/ai-workspace-services/litellm.git`, adding `litellm_source_repo` / `litellm_version` variables for pinning.

---

## 10. Concurrency Optimization Design (Deep Analysis + Custom Strategy)

> Goal: Improve single-machine deployment speed **without dropping tasks, breaking existing role structures, or sacrificing stability**.
> Overall Strategy: Three-phase execution — **Phase 1 Sequential (system global/lock grabbing) → Phase 2 Concurrent (mutually independent I/O) → Phase 3 Sequential (deterministic closing)**. Do not blindly convert multiple roles to concurrent; only make tasks that are "time-consuming, independent, non-writing to the same file, non-grabbing the same lock" `async`, and finally close with `async_status`.

### 10.1 Three-Phase Model (Authoritative Definition)

**Phase 1 — Must be sequential** (grabbing locks / modifying system global state):
`apt update`, `apt install`, `dpkg` related, adding apt repo / keyring, user/group creation, base directory creation, base permissions setting, Docker installation, Caddy installation, systemd base preparation, basic firewall rules, **global pip / global npm(-g) installation**.

**Phase 2 — Can be concurrent** (mutually independent, no same-file writing, no same-lock grabbing):
`docker pull` multiple images, downloading multiple binaries, `git clone` multiple repos, `go build`, `npm/pnpm install` in **different directories**, frontend builds in **different directories**, pulling plugins, pulling static assets, generating non-conflicting service configurations, initializing independent working directories for each service, independent prepare scripts for each service.

**Phase 3 — Must be sequential** (deterministic closing):
Rendering final configurations, `systemd daemon-reload`, `enable service`, `start/restart` in dependency order, health checks, outputting deployment results, cleaning temporary files.

### 10.2 Key Customization Conclusions (Deep Analysis for this Playbook)

1. **All `npm -g` share the same prefix → must be Phase 1 sequential.**
   `roles/vhosts/nodejs` sets `npm_config_prefix=/usr/local/lib/npm`; Agent CLI (opencode-ai / @google/gemini-cli / @openai/codex / @anthropic-ai/claude-code), `yarn`, `openclaw@ver` all use `npm -g` to this prefix. Concurrency would contend for the same `node_modules`/`.staging` and npm cache lock → **Cannot be concurrent**.
2. **LiteLLM has been changed to a standalone Python 3.13 venv, but dependency installation must still be sequential closing**. It no longer writes to system site-packages, but `pip install litellm[proxy]` has a large dependency tree and high network failure rate. The default direction should be to consume offline wheelhouse first, with online venv installation only as a fallback.
3. **Truly safe Phase 2 candidates are "External I/O prefetching"**: git clone, binary downloads, docker pull, frontend builds in separate directories, runtime release downloads. They do not touch dpkg/npm-prefix/pip global locks and write to their own distinct paths.
4. **The greatest concurrency benefit across sub-playbooks is at the Shell prefetch layer**: 11 steps are sequentially imported by ansible, making inter-play concurrency difficult; lifting parallelizable I/O to the Phase 2 fork pool in bootstrap (§10.5) for prefetching, while ansible only consumes ready artifacts, yields the highest risk/reward ratio.
5. **Offline packages priority** (addresses TODO): When offline installation packages/imported images exist, Phase 2 prefetching should short-circuit and skip, directly reusing caches.

### 10.3 Current Tasks → Three-Phase Mapping

| Step / Role | Phase 1 (Sequential) | Phase 2 (Concurrent prefetchable) | Phase 3 (Sequential closing) |
|---|---|---|---|
| 1 nodejs | nodesource keyring/repo, `apt install nodejs`, `npm -g yarn` | — | — |
| 2 console | apt(caddy/xfce4/python3/golang-go/chrome)+chrome repo/key, users/dirs/perms | `get_url` ttyd binary, `git clone` console, dashboard `npm install && build` (independent dir) | render systemd unit/env/portal-services.json, `daemon-reload`/enable/restart, Caddy write+reload |
| 3 ai_agent_runtime | `npm -g` Agent CLI, global pip(python deps), apt(browser/docs/fonts), Playwright(-g) | `agent_skills` pull core-skills market (independent dir) | validation/health, register output |
| 4 gateway_openclaw | `npm -g openclaw@ver`+plugins | (plugins can be concurrent if pulled to independent dirs) | configuration rendering, systemd, version assert, health |
| 5 bridge + ACP | sync console; global install parts of acp_server_* | `xworkmate-go-core` binary download/placement, acp independent working directory prepare | render configs, start in `requires acp-*.service` order, validation |
| 6 vault | (systemd base prep) | `get_url` vault zip download, extract and place | render config, systemd/init, health |
| 7 postgres | Docker install, common base | `docker pull` PG image, initialize independent data dir | compose render, `compose up`, health |
| 8 litellm | apt/Homebrew Python prep, Python 3.13 venv creation, offline wheelhouse or fallback pip install | Download `litellm-runtime-<distro>-<version>-<arch>.tar.gz`, SHA256 validation, prep `packages/pip`/`metadata/runtime.env` | Config render, Prisma client generate, systemd/launchd, health(`:4000/health`) |
| 9 qmd | (bun runtime install, global) | conditional concurrency: pull qmd/`bun install` (isolated to `~/.bun`, does not touch dpkg) | qmd.env/index.yml render, systemd --user, health(`:8181`) |
| 11 xfce (opt) | apt desktop packages/xrdp/chrome, `npm -g`/Playwright | — | xrdp service enable/start, session config |

> Note: Items marked "conditional concurrency" (like qmd `bun`) are included in Phase 2 only when confirmed to write strictly to the service's own user directory and not contend for global locks with other installations at the same time; otherwise, they fall into Phase 1.

### 10.4 Ansible Layer async Mode (Retaining all properties)

Within **a single play**, initiate Phase 2 tasks using `poll:0` and centrally close them with `async_status`. `register`/`when`/`notify`/`tags`/`become`/`failed_when` are always retained:

```yaml
- name: Download ttyd binary (async)
  ansible.builtin.get_url: { url: "...", dest: "{{ ttyd_path }}", mode: "0755" }
  async: 1800
  poll: 0
  register: ttyd_job

- name: Clone xworkspace-console (async)
  ansible.builtin.git: { repo: "...", dest: "{{ repo_dir }}", version: main, depth: 1 }
  become_user: "{{ xworkspace_console_user }}"
  async: 1800
  poll: 0
  register: console_clone_job

# ...other independent Phase 2 tasks initiated with poll:0...

- name: Collect async Phase-2 jobs
  ansible.builtin.async_status: { jid: "{{ item }}" }
  register: p2
  until: p2.finished
  retries: 120
  delay: 5
  loop:
    - "{{ ttyd_job.ansible_job_id }}"
    - "{{ console_clone_job.ansible_job_id }}"
```

- Iron rule for closing: Any Phase 2 product must be `finished` **before being consumed by Phase 3**.
- dpkg / global npm / global pip are **never** `async`; although LiteLLM venv installation is no longer a global pip, it should also run sequentially after the wheelhouse preparation is complete, facilitating failure isolation and retry (§10.2).

### 10.5 Shell Layer Dynamic fork Concurrency (≤ CPU Cores × 2, prefetch layer)

Bootstrap converges parallelizable external I/O into a **load-adaptive bounded fork pool**, used before ansible (Phase 2 prefetch) and at the summary stage. The hard limit is 2 times the online CPU cores of the target host; `AI_WORKSPACE_MAX_PARALLEL_JOBS` can set a lower manual limit, defaulting to `auto`. Before starting each sub-task, it reads the 1-minute load average, dynamically shrinking based on `min(manual limit, 2 × CPU - ceil(load1))`, reserving at least 1 slot:

```bash
CPU_COUNT="$(getconf _NPROCESSORS_ONLN)"
HARD_LIMIT=$((CPU_COUNT * 2))
LOAD_CEILING="$(awk -v load="$(cut -d' ' -f1 /proc/loadavg)" 'BEGIN { n=int(load); print load > n ? n + 1 : n }')"
DYNAMIC_LIMIT=$((HARD_LIMIT - LOAD_CEILING))
[ "$DYNAMIC_LIMIT" -ge 1 ] || DYNAMIC_LIMIT=1

run_bounded() {
  while [ "$(jobs -rp | wc -l)" -ge "$DYNAMIC_LIMIT" ]; do wait -n; done
  "$@" &
}

# Phase 2 prefetch: pull 5 repos + download binaries + pull images (short-circuited if offline packages exist)
for r in playbooks console core-skills qmd litellm; do run_bounded fetch_repo "$r"; done
for b in ttyd vault xworkmate-go-core; do run_bounded fetch_binary "$b"; done
for img in "${PG_IMAGES[@]}"; do run_bounded docker_pull "$img"; done
for p in "${pids[@]}"; do wait "$p" || rc=1; done
[ "$rc" -eq 0 ] || { echo "[phase2] Sub-tasks failed"; exit 1; }
```

- Health check fan-out (before summary): Use the same dynamic limit for `systemctl is-active` + `curl` health endpoints of Portal/Bridge/OpenClaw/QMD/Hermes/PG/Vault/LiteLLM, summarizing them in a fixed order.
- Each child process has a log prefix (`[repo:qmd]`/`[bin:vault]`), exits non-zero on failure, and is not silenced.
- Sequential preservation: The main `ansible-playbook` execution (Phase 1/Phase 3 guaranteed internally), one-time token/summary printing.

### 10.6 Content that Must Not Be Lost (Hard Constraints)

Retain all existing tasks and properties one by one: `apt/package`, users/dirs/perms, env files, systemd unit rendering, Caddy/Nginx, Docker/compose, service starts, health checks, `debug`, failure handling, `handlers`, `tags`, `become`, `when`, `notify`, `register`. **Do not delete/merge/skip any existing task for the sake of concurrency**; only change "when to wait" (`poll:0`+`async_status`), not "what to do".

### 10.7 Safe Global Acceleration (Complementary to async, does not change task semantics)

`ansible.cfg` (already exists) can overlay low-risk items:

```ini
[defaults]
gathering = smart
fact_caching = jsonfile
fact_caching_connection = /tmp/ansible_facts
[ssh_connection]
pipelining = true
```

And address TODO concerns: APT/deployment locks require **safe waiting** (retry rather than forceful lock deletion) to ensure secondary idempotent execution succeeds. `strategy: free` offers limited single-machine benefit and changes the execution feel, so it is **disabled by default**.

### 10.8 Acceptance (Equivalence Regression)

- [ ] The task sets from `ansible-playbook --list-tasks` are identical before and after optimization (no loss/merges).
- [ ] Every `async` task has a corresponding `async_status` close, with no dangling jobs.
- [ ] Phase 1 (apt/global npm/global pip/dpkg, LiteLLM venv install) and Phase 3 (daemon-reload/enable/start/health/summary/cleanup) remain strictly sequential.
- [ ] Phase 2 tasks do not write to the same file or grab the same lock; they short-circuit and skip when offline packages exist.
- [ ] Two consecutive executions both succeed; the idempotent behavior of `changed=0` remains unchanged; failed sub-tasks in the Shell fork pool exit non-zero with visible logs.

---
