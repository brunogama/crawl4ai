#!/usr/bin/env bash
# Install Crawl4AI dependencies from explicit GitHub sources only.
#
# This script intentionally does not use package-name-only requirements,
# requirements.txt, PyPI, Poetry/PDM/uv resolution, conda, or pip dependency
# resolution. Every dependency must be listed in scripts/github-deps.json with
# a GitHub repo URL and a reviewed ref before installation can proceed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MANIFEST="${SCRIPT_DIR}/github-deps.json"
VENV_DIR="${PROJECT_ROOT}/.venv-github-deps"
PYTHON_BIN="${PYTHON:-python3}"
DRY_RUN=0
LIST_ONLY=0
SKIP_PROJECT=0
ALLOW_BRANCH_REFS=0
CLEAN_SRC=0

usage() {
	cat <<'USAGE'
Usage: scripts/install-github-deps.sh [options]

Options:
  --manifest PATH       Dependency source manifest (default: scripts/github-deps.json)
  --venv PATH           Virtual environment path (default: .venv-github-deps)
  --python PATH         Python executable used to create the venv (default: python3 or $PYTHON)
  --dry-run             Validate and print planned operations without cloning/installing
  --list                Validate and list manifest entries, then exit
  --skip-project        Install dependencies only; do not install the local project
  --allow-branch-refs   Permit manifest entries with ref_type="branch" or allow_branch=true
                       Note: per project instruction, missing refs default to branch "main"
                       when repo is present.
  --clean-src           Remove cached Git clones before installing
  -h, --help            Show this help

Manifest requirements:
  - JSON array of entries.
  - Each entry must include name, repo, ref, ref_type, install_subdir, extras,
    dependency_type, and required_by.
  - repo must be an https://github.com/... URL.
  - ref_type must be "commit" or "tag"; "branch" is rejected unless explicitly allowed.
  - Per project instruction, entries with repo but no ref default to branch "main".
  - Entries without repo are unresolved and make the script fail closed.
USAGE
}

log() { printf '[github-deps] %s\n' "$*"; }
fatal() {
	printf '[github-deps] ERROR: %s\n' "$*" >&2
	exit 1
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	--manifest)
		MANIFEST="$2"
		shift 2
		;;
	--venv)
		VENV_DIR="$2"
		shift 2
		;;
	--python)
		PYTHON_BIN="$2"
		shift 2
		;;
	--dry-run)
		DRY_RUN=1
		shift
		;;
	--list)
		LIST_ONLY=1
		shift
		;;
	--skip-project)
		SKIP_PROJECT=1
		shift
		;;
	--allow-branch-refs)
		ALLOW_BRANCH_REFS=1
		shift
		;;
	--clean-src)
		CLEAN_SRC=1
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	*) fatal "Unknown argument: $1" ;;
	esac
done

[[ -f "${MANIFEST}" ]] || fatal "Manifest not found: ${MANIFEST}"
command -v git >/dev/null 2>&1 || fatal "git is required"
command -v "${PYTHON_BIN}" >/dev/null 2>&1 || fatal "Python executable not found: ${PYTHON_BIN}"

VALIDATED_TSV="$(mktemp)"
trap 'rm -f "${VALIDATED_TSV}"' EXIT

ALLOW_BRANCH_REFS="${ALLOW_BRANCH_REFS}" "${PYTHON_BIN}" - "${MANIFEST}" >"${VALIDATED_TSV}" <<'PY'
import json
import os
import re
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
allow_branch_cli = os.environ.get("ALLOW_BRANCH_REFS") == "1"
default_missing_ref_to_main = True
try:
    data = json.loads(manifest_path.read_text())
except Exception as exc:
    print(f"Manifest is not valid JSON: {exc}", file=sys.stderr)
    sys.exit(2)

if not isinstance(data, list):
    print("Manifest must be a JSON array", file=sys.stderr)
    sys.exit(2)

sha_re = re.compile(r"^[0-9a-fA-F]{40,64}$")
unresolved = []
errors = []
seen = set()

for index, entry in enumerate(data):
    if not isinstance(entry, dict):
        errors.append(f"entry #{index}: must be an object")
        continue
    name = str(entry.get("name") or "").strip()
    repo = str(entry.get("repo") or "").strip()
    ref = str(entry.get("ref") or "").strip()
    ref_type = str(entry.get("ref_type") or "").strip().lower()
    install_subdir = str(entry.get("install_subdir") or ".").strip()
    dependency_type = str(entry.get("dependency_type") or "").strip()
    required_by = entry.get("required_by") or []
    extras = entry.get("extras") or []
    allow_branch_entry = bool(entry.get("allow_branch"))

    if not name:
        errors.append(f"entry #{index}: missing name")
        continue
    if name in seen:
        errors.append(f"{name}: duplicate manifest entry")
    seen.add(name)
    if not repo:
        reason = entry.get("unresolved_reason") or "missing repo"
        unresolved.append(f"{name}: {reason}")
        continue
    if not ref and default_missing_ref_to_main:
        ref = "main"
        ref_type = "branch"
        allow_branch_entry = True
    elif not ref:
        reason = entry.get("unresolved_reason") or "missing ref"
        unresolved.append(f"{name}: {reason}")
        continue
    if not (repo.startswith("https://github.com/") and (repo.endswith(".git") or ".git#" not in repo)):
        errors.append(f"{name}: repo must be an https://github.com/... URL: {repo}")
    if ref_type not in {"commit", "tag", "branch"}:
        errors.append(f"{name}: ref_type must be commit, tag, or branch")
    if ref_type == "commit" and not sha_re.fullmatch(ref):
        errors.append(f"{name}: ref_type=commit requires a 40+ hex commit SHA")
    if ref_type == "branch" and not (allow_branch_cli or allow_branch_entry):
        errors.append(f"{name}: branch refs are rejected unless --allow-branch-refs or allow_branch=true is set")
    if not isinstance(extras, list) or not all(isinstance(x, str) for x in extras):
        errors.append(f"{name}: extras must be an array of strings")
        extras = []
    if not isinstance(required_by, list) or not all(isinstance(x, str) for x in required_by):
        errors.append(f"{name}: required_by must be an array of strings")
    if "\t" in name + repo + ref + install_subdir + dependency_type:
        errors.append(f"{name}: tab characters are not supported in scalar fields")

    extras_field = ",".join(extras) if extras else "-"
    print("\t".join([name, repo, ref, ref_type, install_subdir, extras_field, dependency_type]))

if unresolved:
    print("Unresolved dependencies (fill repo/ref/ref_type in the manifest):", file=sys.stderr)
    for item in unresolved:
        print(f"  - {item}", file=sys.stderr)
if errors:
    print("Manifest validation errors:", file=sys.stderr)
    for item in errors:
        print(f"  - {item}", file=sys.stderr)
if unresolved or errors:
    sys.exit(1)
PY

if [[ "${LIST_ONLY}" == "1" || "${DRY_RUN}" == "1" ]]; then
	log "Validated manifest entries:"
	while IFS=$'\t' read -r name repo ref ref_type install_subdir extras dependency_type; do
		printf '  - %s [%s] %s@%s (%s) subdir=%s extras=%s\n' \
			"${name}" "${dependency_type}" "${repo}" "${ref}" "${ref_type}" "${install_subdir}" "${extras:-none}"
	done <"${VALIDATED_TSV}"
	[[ "${LIST_ONLY}" == "1" ]] && exit 0
fi

if [[ "${DRY_RUN}" == "1" ]]; then
	log "Dry run complete; no clone or install operations were performed."
	exit 0
fi

log "Creating/reusing virtual environment: ${VENV_DIR}"
"${PYTHON_BIN}" -m venv "${VENV_DIR}"
# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"

export PIP_NO_INDEX=1
export PIP_NO_DEPS=1
export PIP_DISABLE_PIP_VERSION_CHECK=1
export PIP_REQUIRE_VIRTUALENV=1
export PIP_NO_INPUT=1
unset PIP_INDEX_URL PIP_EXTRA_INDEX_URL PIP_FIND_LINKS || true

SRC_DIR="${VENV_DIR}/github-src"
if [[ "${CLEAN_SRC}" == "1" ]]; then
	rm -rf "${SRC_DIR}"
fi
mkdir -p "${SRC_DIR}"

safe_component() {
	printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'
}

install_entry() {
	local name="$1" repo="$2" ref="$3" ref_type="$4" install_subdir="$5" extras="$6" dependency_type="$7"
	local clone_dir="${SRC_DIR}/$(safe_component "${name}")-$(safe_component "${ref}")"
	local install_path extras_suffix

	log "Installing ${name} (${dependency_type}) from ${repo}@${ref}"
	if [[ ! -d "${clone_dir}/.git" ]]; then
		git clone "${repo}" "${clone_dir}"
	else
		git -C "${clone_dir}" remote set-url origin "${repo}"
		git -C "${clone_dir}" fetch --tags --force origin
	fi
	git -C "${clone_dir}" checkout --detach "${ref}"

	install_path="${clone_dir}"
	if [[ "${install_subdir}" != "." ]]; then
		install_path="${clone_dir}/${install_subdir}"
	fi
	[[ -d "${install_path}" ]] || fatal "Install subdirectory not found for ${name}: ${install_subdir}"

	extras_suffix=""
	if [[ "${extras}" != "-" && -n "${extras}" ]]; then
		extras_suffix="[${extras}]"
	fi

	python -m pip install \
		--disable-pip-version-check \
		--no-input \
		--no-index \
		--no-deps \
		--no-build-isolation \
		"${install_path}${extras_suffix}"
}

while IFS=$'\t' read -r name repo ref ref_type install_subdir extras dependency_type; do
	install_entry "${name}" "${repo}" "${ref}" "${ref_type}" "${install_subdir}" "${extras}" "${dependency_type}"
done <"${VALIDATED_TSV}"

if [[ "${SKIP_PROJECT}" != "1" ]]; then
	log "Installing local project without dependency resolution"
	python -m pip install \
		--disable-pip-version-check \
		--no-input \
		--no-index \
		--no-deps \
		--no-build-isolation \
		"${PROJECT_ROOT}"
fi

log "Done. Virtual environment: ${VENV_DIR}"
