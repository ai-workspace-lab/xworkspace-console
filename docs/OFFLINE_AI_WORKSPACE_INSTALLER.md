# Offline AI Workspace Installer

`offline-package-ai-workspace-installer.yaml` builds tarball resource packs for
`setup-ai-workspace-all-in-one.sh`.

## Supported Targets

- Debian: 13, 12, 11
- Ubuntu LTS: 26.04, 24.04, 22.04
- Architectures: amd64, arm64

Ubuntu 20.04 is not in the default matrix because standard support has moved to
Ubuntu Pro/ESM.

## Package Contents

- `repos/playbooks`
- `repos/xworkspace-console`
- `repos/xworkspace-core-skills`
- `repos/xworkmate-bridge`
- `repos/qmd`
- `repos/litellm`
- `packages/apt`
- `packages/npm`
- `packages/npm-cache`
- `packages/pip`
- `packages/bin`
- `packages/images`
- `scripts/ai-workspace-offline-install.sh`
- `metadata/manifest.json`
- `metadata/*.commit`

## Runtime Usage

Extract the target package on the host and run:

```bash
sudo ./scripts/ai-workspace-offline-install.sh
```

The script configures a local APT repository, installs bundled binaries, loads
packaged container images when Docker is available, and runs the packaged
all-in-one bootstrap with local source directories.

## Deployment Timing Notes

A remote `setup-ai-workspace-all-in-one.sh` run on `acp-bridge.onwalk.net`
showed these visible timing hotspots:

- OpenClaw npm package/plugin install and dependency repair: about 68 seconds
- Codex ACP Go build: about 37 seconds
- ACP vhosts for Codex/OpenCode/Gemini/Hermes: about 95 seconds
- Console runtime apt/package setup and ttyd: about 47 seconds
- Agent skill sync and quality checks: about 48 seconds

The first several minutes of the sampled log included Node, apt, and AI runtime
setup before the captured timing window. Those are treated as resource-heavy
setup phases and are included in the offline package through APT caches, npm
tarballs, pip wheels, local git sources, binaries, and container image tarballs.
