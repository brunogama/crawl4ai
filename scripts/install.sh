#!/usr/bin/env bash
# Project installer that delegates dependency installation to the GitHub-only
# manifest installer. This avoids PyPI/package-name dependency resolution.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/install-github-deps.sh" "$@"
