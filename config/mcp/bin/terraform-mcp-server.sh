#!/usr/bin/env bash
set -euo pipefail
exec docker run --rm -i \
  ghcr.io/hashicorp/terraform-mcp-server:latest \
  --toolsets=registry
