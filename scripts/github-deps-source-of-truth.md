# GitHub-only dependency manifest source of truth

Bowser research conclusion: use `pyproject.toml` as the authoritative source for this repository's direct runtime dependencies.

Rationale:

- `pyproject.toml` declares PEP 621 `[project].dependencies`.
- `setup.py` says most configuration moved to `pyproject.toml` and does not declare `install_requires`.
- `requirements.txt` claims to mirror `pyproject.toml`, but currently differs.
- `uv.lock` is generated resolver output and is currently stale/inconsistent with `pyproject.toml`; use a regenerated lock only as inventory assistance, not as direct dependency authority.

Installer ref policy:

- Commit SHA remains preferred and reviewed tags are acceptable.
- Per user instruction, if a manifest entry has a GitHub `repo` but no `ref`, the installer treats it as branch `main`.
- Entries without a GitHub `repo` still fail closed.

Official repository discovery:

- Bowser checked official package/project pages and populated `scripts/github-deps.json` with GitHub repository URLs for all build/direct dependencies.
- `beautifulsoup4`'s official source is Launchpad (`https://code.launchpad.net/beautifulsoup`) via the official Beautiful Soup site. The user approved a GitHub fork/source for this exception.
- Bowser found no apparent upstream-maintained GitHub repo for Beautiful Soup, so `beautifulsoup4` uses `https://github.com/qundao/mirror-beautifulsoup4` pinned to commit `974559b0e411a92c0422f5a6c26b78e676ec457e` (tag `4.14.3`). Caveat: this is a third-party mirror; compare against official Launchpad/PyPI source if stronger supply-chain assurance is required.
- Bowser researched transitive runtime dependency metadata and `scripts/github-deps.json` now includes those transitive packages with official GitHub repositories where found. The `_transitive_dependencies_unresolved` blocker was removed.
- Transitive entries also use the user-approved missing-ref policy: if `ref` is omitted, the installer checks out `main`.

Important mismatches to preserve correctly:

- Use `unclecode-litellm==1.81.13` from `pyproject.toml`, not stale `uv.lock` package `litellm`.
  - Package/repo evidence: <https://pypi.org/project/unclecode-litellm/> and <https://github.com/unclecode/litellm>
  - It installs/imports as `litellm`, explaining source imports such as `from litellm import completion`.
- Use `playwright-stealth>=2.0.0` from `pyproject.toml`, not stale `uv.lock` package `tf-playwright-stealth`.
  - Package/repo evidence: <https://pypi.org/project/playwright-stealth/> and <https://github.com/Mattwmaster58/playwright_stealth>
- Treat `requirements.txt`-only entries (`colorama`, `pdf2image`, `pypdf`) as non-authoritative for runtime unless project maintainers explicitly decide otherwise.

Authoritative references:

- Upstream `pyproject.toml`: <https://raw.githubusercontent.com/unclecode/crawl4ai/main/pyproject.toml>
- PyPA dependency metadata spec: <https://packaging.python.org/en/latest/specifications/declaring-project-metadata/#dependencies-optional-dependencies>
