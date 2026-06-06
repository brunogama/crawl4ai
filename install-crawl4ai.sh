#!/usr/bin/env bash
# Crawl4AI installer entrypoint.
# Delegates dependency and project installation to the GitHub-only installer.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${ROOT_DIR}/scripts/install-github-deps.sh" "$@"
