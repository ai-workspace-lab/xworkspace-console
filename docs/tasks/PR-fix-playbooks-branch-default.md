# PR: fix/playbooks-branch-default

## Summary
Change `BRANCH` default in `run-on-host-bootstrap.sh` from `fix-standalone-vault` back to `main`.

## Context
During the standalone Vault deployment fix cycle (July 2026), the `BRANCH` variable in
`run-on-host-bootstrap.sh` was temporarily hardcoded to `fix-standalone-vault` so that
CI deployments would use the in-progress Vault fixes on the playbooks repo.

All vault fixes have since been merged into `playbooks/main`:
- PostgreSQL schema creation before Vault start
- `wait_for` PostgreSQL port before Vault start
- `setup-vault.yaml` slurp shadow file for `vault_pg_password`
- `create_databases_and_users.yml` persist shadow file
- Vault diagnostics on failure (systemctl/journal)

The hardcoded branch default should now return to `main`.

## Changes
| File | Change |
|------|--------|
| `scripts/run-on-host-bootstrap.sh:57` | `PLAYBOOKS_BRANCH` default: `fix-standalone-vault` → `main` |

## Related
- Playbooks repo PRs: #106–#114 (vault fixes)
- Conversation: `2f521e13-c13e-4df8-b2d9-cd8883afff30`

## Verification
- CI workflow `deploy-ai-workspace-iac.yaml` should deploy successfully with `BRANCH=main`
- Both Ubuntu and Debian hosts should pass `Wait for standalone Vault API`
