#!/usr/bin/env bash
# apply.sh - bring a repository into the state way-a/0001-community-files describes.
#
# Run by the runner (wamp-cicd fleet/apply-rollout.sh) from the member repository's root, on the
# rollout branch, with a clean tree. It changes files and stages them; it never commits, pushes or
# talks to a forge, and needs no credentials. Re-runnable: a second run changes nothing.
#
# What it does - the mechanical part of what wave 1 did by hand:
#   1. the tooling pins, at the commits in rollout.toml (never moved backwards):
#        an ordinary member   .cicd and .ai as submodules
#        wamp-cicd            wamp-ai in deps.toml / .deps/, and the policy files linked from it
#        wamp-ai              wamp-cicd in deps.toml / .deps/, and the managed copies from it
#   2. the shared community files, deployed from wamp-cicd's templates (DEVELOPMENT.md is only
#      seeded: an existing one is the repository's own and is kept);
#   3. the justfile has the Way-A workflow recipes (created if there is no justfile);
#   4. CI runs the community files check: if no workflow does, .github/workflows/fleet.yml is added.
#
# What it leaves to a follow-up commit on the same branch, because it takes judgement: moving the
# repository's own content out of an old CONTRIBUTING.md into DEVELOPMENT.md BEFORE this runs
# (deploy replaces CONTRIBUTING.md), recipe names that collide with workflow.just, the changelog.

set -euo pipefail
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
: "${FLEET_DEF_DIR:?run by the runner (wamp-cicd fleet/apply-rollout.sh)}" "${FLEET_SLUG:?}" "${FLEET_DEFAULT_BRANCH:?}"
die() { echo "ERROR: $*" >&2; exit 1; }
# shellcheck source=/dev/null
. "${HERE}/layout.sh"

# 1. The pins.
case "${LAYOUT}" in
    ordinary)
        set_pin .cicd "${CICD_URL}" "$(pin_of cicd)"
        set_pin .ai   "${AI_URL}"   "$(pin_of ai)" ;;
    cicd)
        set_dep wamp-ai "${AI_URL}" "$(pin_of ai tooling)" .ai
        for pair in CLAUDE.md:AI_GUIDELINES.md AI_POLICY.md:AI_POLICY.md; do
            [ -e "${pair%%:*}" ] || [ -L "${pair%%:*}" ] || { ln -s ".deps/wamp-ai/${pair#*:}" "${pair%%:*}"; echo "  linked     ${pair%%:*} -> .deps/wamp-ai/${pair#*:}"; }
            git add "${pair%%:*}"
        done ;;
    ai)
        set_dep wamp-cicd "${CICD_URL}" "$(pin_of cicd tooling)" .cicd
        for f in "${MANAGED_COPIES[@]}"; do
            if cmp -s ".deps/wamp-cicd/${f}" "${f}"; then echo "  unchanged  ${f}"
            else mkdir -p "$(dirname "${f}")"; cp -p ".deps/wamp-cicd/${f}" "${f}"; echo "  deployed   ${f} (a managed copy from .deps/wamp-cicd)"; fi
            git add "${f}"
        done ;;
esac

# 2. The community files.
bash "${P}scripts/community-files.sh" deploy . | sed '$d'
git add -A -- CONTRIBUTING.md DEVELOPMENT.md .audit/README.md .github

# 3. The Way-A workflow recipes.
python3 - "${FLEET_DEFAULT_BRANCH}" "${LAYOUT}" <<'PY'
import os, re, sys
main, layout = sys.argv[1], sys.argv[2]
# What the justfile imports: its own file (wamp-cicd), the submodule's, or - in wamp-ai, where
# the checkout is optional until `just deps` has run - the pinned checkout's, if it is there.
imp = {"ordinary": "import '.cicd/workflow.just'", "cicd": "import 'workflow.just'",
       "ai": "import? '.deps/wamp-cicd/workflow.just'"}[layout]
has = re.compile(r"import\??\s+['\"]" + re.escape(re.search(r"'(.*)'", imp).group(1)) + r"['\"]")
where = {"ordinary": ".cicd/workflow.just", "cicd": "workflow.just", "ai": ".deps/wamp-cicd/workflow.just"}[layout]
block = [
    "# -----------------------------------------------------------------------------",
    f"# -- Way-A shared workflow recipes (wamp-cicd / {where})",
    "# -----------------------------------------------------------------------------",
]
if main != "main":
    block += [
        f"# This repo's default branch is `{main}` (not `main`). Override WORKFLOW_MAIN",
        "# BEFORE the import so the main-justfile definition wins over workflow.just's",
        "# default of 'main'. Do NOT also `set allow-duplicate-variables` here -",
        "# workflow.just owns that setting (setting it twice is a hard `just` error).",
        f"WORKFLOW_MAIN := '{main}'",
    ]
block += [imp]
deps = ["# Make `.deps/` what `deps.toml` says: this repository's dependencies as plain checkouts at pinned commits - it carries no submodules (see TOOLING-STRUCTURE.md).",
        "deps *args:", "    bash scripts/deps.sh sync {{args}}"]
if not os.path.exists("justfile"):
    lines = block + ["", "# List all recipes.", "default:", "    @just --list", ""]
    open("justfile", "w").write("\n".join(lines))
    print(f"  created    justfile (imports {where})")
    sys.exit(0)
lines = open("justfile").read().split("\n")
changed = []
if not any(has.match(l) for l in lines):
    # After the last top-level `set ...` line; without one, after the leading comment header.
    at = max((i + 1 for i, l in enumerate(lines) if re.match(r"set\s+\S", l)), default=None)
    if at is None:
        at = 0
        while at < len(lines) and lines[at].startswith("#"):
            at += 1
    lines[at:at] = [""] + block + ([] if at < len(lines) and lines[at] == "" else [""])
    changed.append(f"imports {where}")
if layout == "ai" and not any(re.match(r"deps(\s|:)", l) for l in lines):
    while lines and lines[-1] == "":
        lines.pop()
    lines += [""] + deps + [""]
    changed.append("recipe `deps`")
if changed:
    open("justfile", "w").write("\n".join(lines))
    print(f"  changed    justfile ({', '.join(changed)})")
else:
    print(f"  unchanged  justfile (imports {where})")
PY
git add justfile
if command -v just >/dev/null 2>&1; then
    just --list >/dev/null || die "the justfile does not load with workflow.just imported (a duplicate setting or recipe name?) - fix that in a commit of its own, then re-run"
fi

# 4. The drift check in CI.
if grep -r -q -s -F "run: bash ${P}scripts/community-files.sh check" .github/workflows; then
    echo "  unchanged  CI (a workflow runs the community files check)"
else
    mkdir -p .github/workflows
    [ ! -e .github/workflows/fleet.yml ] || die ".github/workflows/fleet.yml exists but does not run the community files check"
    # One template for the three layouts: lines tagged for another layout are dropped, the tags
    # removed, and the path to wamp-cicd filled in.
    sed -e "/#@only:/{/#@only:[a-z,]*${LAYOUT}/!d}" -e 's/ *#@only:[a-z,]*$//' \
        -e "s|@@MAIN@@|${FLEET_DEFAULT_BRANCH}|" -e "s|@@P@@|${P}|g" "${HERE}/fleet.yml" > .github/workflows/fleet.yml
    echo "  created    .github/workflows/fleet.yml"
fi
git add .github/workflows

[ "${LAYOUT}" != ordinary ] || [ -e CLAUDE.md ] || echo "  note       no CLAUDE.md / AI_POLICY.md here: run \`just setup-repo\` in .ai (a follow-up commit)"
"${HERE}/check.sh"
