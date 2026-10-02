#!/usr/bin/env bash
# apply.sh - bring a repository into the state way-a/0001-community-files describes.
#
# Run by the runner (wamp-cicd fleet/apply-rollout.sh) from the member repository's root, on the
# rollout branch, with a clean tree. It changes files and stages them; it never commits, pushes or
# talks to a forge, and needs no credentials. Re-runnable: a second run changes nothing.
#
# What it does - the mechanical part of what wave 1 did by hand:
#   1. .cicd and .ai: submodules, at the commits in rollout.toml [pins] (never moved backwards);
#   2. the shared community files, deployed from .cicd/templates/ (DEVELOPMENT.md is only seeded:
#      an existing one is the repository's own and is kept);
#   3. the justfile imports .cicd/workflow.just (created if there is none);
#   4. CI runs the community files check: if no workflow does, .github/workflows/fleet.yml is added.
#
# What it leaves to a follow-up commit on the same branch, because it takes judgement: moving the
# repository's own content out of an old CONTRIBUTING.md into DEVELOPMENT.md BEFORE this runs
# (deploy replaces CONTRIBUTING.md), recipe names that collide with workflow.just, the changelog.

set -euo pipefail
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
: "${FLEET_DEF_DIR:?run by the runner (wamp-cicd fleet/apply-rollout.sh)}" "${FLEET_SLUG:?}" "${FLEET_DEFAULT_BRANCH:?}"
die() { echo "ERROR: $*" >&2; exit 1; }

# The two sources of the shared tooling cannot pin themselves, and must not carry submodules at
# all: every member pins them, so a submodule in them is cloned by every recursive checkout of
# every member, one level deeper with each bump.
case "${FLEET_SLUG}" in
    wamp-proto/wamp-cicd|wamp-proto/wamp-ai)
        die "${FLEET_SLUG} is a source of the shared tooling: it cannot take this rollout (see rollout.toml)" ;;
esac

pin_of() { python3 - "${HERE}/rollout.toml" "$1" <<'PY'
import sys
try:
    import tomllib
except ImportError:  # Python < 3.11
    import tomli as tomllib
print(tomllib.load(open(sys.argv[1], "rb"))["pins"][sys.argv[2]])
PY
}

# set_pin <path> <forge url> <commit>: <path> is a submodule at <commit>, or later if it already is.
# Objects come from the definition clone's own checkout of the same submodule when it has one (no
# network), else from the forge. .gitmodules records the forge URL either way.
set_pin() {
    local path="$1" url="$2" want="$3" src="${FLEET_DEF_DIR}/$1" have recorded added=0
    [ -e "${src}/.git" ] || src="${url}"
    recorded="$(git config -f .gitmodules --get "submodule.${path}.url" 2>/dev/null || true)"
    if [ ! -e "${path}/.git" ]; then
        if [ -n "${recorded}" ]; then
            git submodule --quiet init "${path}"
            git -c protocol.file.allow=always -c "url.${src}.insteadOf=${recorded}" submodule --quiet update "${path}" \
                || die "could not initialise ${path} from ${src}"
        else
            git -c protocol.file.allow=always submodule add --quiet --force "${src}" "${path}" >/dev/null 2>&1 \
                || die "could not add ${path} from ${src}"
            added=1
        fi
    fi
    git -C "${path}" rev-parse -q --verify "${want}^{commit}" >/dev/null 2>&1 \
        || git -C "${path}" -c protocol.file.allow=always fetch --quiet "${src}" HEAD 2>/dev/null || true
    git -C "${path}" rev-parse -q --verify "${want}^{commit}" >/dev/null 2>&1 \
        || git -C "${path}" fetch --quiet "${url}" 2>/dev/null || true
    want="$(git -C "${path}" rev-parse -q --verify "${want}^{commit}")" || die "${path}: cannot get commit $3 from ${src} or ${url}"
    have="$(git -C "${path}" rev-parse HEAD)"
    if [ "${added}" = 1 ]; then
        # Newly added: exactly the rollout's commit, whatever the source happened to have checked out.
        git -C "${path}" checkout --quiet "${want}"
        echo "  added      ${path} at ${want:0:7}"
    elif git -C "${path}" merge-base --is-ancestor "${want}" "${have}"; then
        echo "  kept       ${path} at ${have:0:7} (at or after ${want:0:7})"
    elif git -C "${path}" merge-base --is-ancestor "${have}" "${want}"; then
        git -C "${path}" checkout --quiet "${want}"
        echo "  pinned     ${path} ${have:0:7} -> ${want:0:7}"
    else
        die "${path} is at ${have:0:7}, which is neither before nor after ${want:0:7}"
    fi
    [ -n "${recorded}" ] || recorded="${url}"
    git config -f .gitmodules "submodule.${path}.url" "${recorded}"
    git config "submodule.${path}.url" "${recorded}"
    git -C "${path}" remote set-url origin "${recorded}" 2>/dev/null || true
    git add .gitmodules "${path}"
}

# 1. The pins.
set_pin .cicd https://github.com/wamp-proto/wamp-cicd.git "$(pin_of cicd)"
set_pin .ai   https://github.com/wamp-proto/wamp-ai.git   "$(pin_of ai)"

# 2. The community files.
bash .cicd/scripts/community-files.sh deploy . | sed '$d'
git add -A -- CONTRIBUTING.md DEVELOPMENT.md .audit/README.md .github

# 3. The Way-A workflow recipes.
python3 - "${FLEET_DEFAULT_BRANCH}" <<'PY'
import os, re, sys
main = sys.argv[1]
block = [
    "# -----------------------------------------------------------------------------",
    "# -- Way-A shared workflow recipes (wamp-cicd / .cicd/workflow.just)",
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
block += ["import '.cicd/workflow.just'"]
if not os.path.exists("justfile"):
    lines = block + ["", "# List all recipes.", "default:", "    @just --list", ""]
    open("justfile", "w").write("\n".join(lines))
    print("  created    justfile (imports .cicd/workflow.just)")
    sys.exit(0)
lines = open("justfile").read().split("\n")
if any(re.match(r"import\s+['\"]\.cicd/workflow\.just['\"]", l) for l in lines):
    print("  unchanged  justfile (imports .cicd/workflow.just)")
    sys.exit(0)
# After the last top-level `set ...` line; without one, after the leading comment header.
at = max((i + 1 for i, l in enumerate(lines) if re.match(r"set\s+\S", l)), default=None)
if at is None:
    at = 0
    while at < len(lines) and lines[at].startswith("#"):
        at += 1
lines[at:at] = [""] + block + [""]
open("justfile", "w").write("\n".join(lines))
print("  changed    justfile (imports .cicd/workflow.just)")
PY
git add justfile
if command -v just >/dev/null 2>&1; then
    just --list >/dev/null || die "the justfile does not load with .cicd/workflow.just imported (a duplicate setting or recipe name?) - fix that in a commit of its own, then re-run"
fi

# 4. The drift check in CI.
if grep -r -q -s -E "^[[:space:]]*run:.*\.cicd/scripts/community-files\.sh check" .github/workflows; then
    echo "  unchanged  CI (a workflow runs the community files check)"
else
    mkdir -p .github/workflows
    [ ! -e .github/workflows/fleet.yml ] || die ".github/workflows/fleet.yml exists but does not run the community files check"
    sed "s|@@MAIN@@|${FLEET_DEFAULT_BRANCH}|" "${HERE}/fleet.yml" > .github/workflows/fleet.yml
    echo "  created    .github/workflows/fleet.yml"
fi
git add .github/workflows

[ -e CLAUDE.md ] || echo "  note       no CLAUDE.md / AI_POLICY.md here: run \`just setup-repo\` in .ai (a follow-up commit)"
"${HERE}/check.sh"
