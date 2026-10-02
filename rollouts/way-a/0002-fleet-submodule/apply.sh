#!/usr/bin/env bash
# apply.sh - bring a repository into the state way-a/0002-fleet-submodule describes.
#
# Run by the runner (wamp-cicd fleet/apply-rollout.sh) from the member repository's root, on the
# rollout branch, with a clean tree. It changes files and stages them; it never commits, pushes or
# talks to a forge, and needs no credentials. Re-runnable: a second run changes nothing.
#
# What it does:
#   1. .cicd: at the commit in rollout.toml [pins] (never moved backwards) - the first version of
#      the tools with fleet/lag-check.sh;
#   2. the shared community files, re-deployed from the templates of that .cicd;
#   3. the lag check as a CI step, directly after the community files check, in every workflow
#      that runs it.
# What it does NOT do: the .fleet submodule and the .waves/ markers. The runner writes those, in
# the same commit, for every rollout.

set -euo pipefail
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
: "${FLEET_DEF_DIR:?run by the runner (wamp-cicd fleet/apply-rollout.sh)}" "${FLEET_SLUG:?}"
die() { echo "ERROR: $*" >&2; exit 1; }

# 1. The pin. Objects come from the definition clone's own .cicd checkout when it has one (no
# network), else from the forge.
[ -e .cicd/.git ] || die ".cicd is not initialised in this clone (git submodule update --init .cicd)"
url="$(git config -f .gitmodules --get submodule..cicd.url)" || die ".cicd is not in .gitmodules"
want="$(python3 - "${HERE}/rollout.toml" <<'PY'
import sys
try:
    import tomllib
except ImportError:  # Python < 3.11
    import tomli as tomllib
print(tomllib.load(open(sys.argv[1], "rb"))["pins"]["cicd"])
PY
)"
if ! git -C .cicd rev-parse -q --verify "${want}^{commit}" >/dev/null 2>&1; then
    [ ! -e "${FLEET_DEF_DIR}/.cicd/.git" ] \
        || git -C .cicd -c protocol.file.allow=always fetch --quiet "${FLEET_DEF_DIR}/.cicd" HEAD 2>/dev/null || true
    git -C .cicd rev-parse -q --verify "${want}^{commit}" >/dev/null 2>&1 \
        || git -C .cicd fetch --quiet "${url}" 2>/dev/null || true
    git -C .cicd rev-parse -q --verify "${want}^{commit}" >/dev/null 2>&1 \
        || die ".cicd: cannot get commit ${want} from ${FLEET_DEF_DIR}/.cicd or ${url}"
fi
have="$(git -C .cicd rev-parse HEAD)"
if git -C .cicd merge-base --is-ancestor "${want}" "${have}"; then
    echo "  kept       .cicd at ${have:0:7} (at or after ${want:0:7})"
elif git -C .cicd merge-base --is-ancestor "${have}" "${want}"; then
    git -C .cicd checkout --quiet "${want}"
    echo "  pinned     .cicd ${have:0:7} -> ${want:0:7}"
else
    die ".cicd is at ${have:0:7}, which is neither before nor after ${want:0:7}"
fi
git add .cicd

# 2. The community files: the copies must match the templates of the .cicd just pinned.
bash .cicd/scripts/community-files.sh deploy . | sed '$d'
git add -A -- CONTRIBUTING.md DEVELOPMENT.md .audit/README.md .github

# 3. The lag check in CI. The slug is written out: a fork's own CI would otherwise look itself up
# in the inventory under the fork's name.
python3 - "${FLEET_SLUG}" <<'PY'
import glob, re, sys
slug = sys.argv[1]
anchor = re.compile(r"^(\s*)run:.*\.cicd/scripts/community-files\.sh check")
seen = 0
for wf in sorted(glob.glob(".github/workflows/*.yml") + glob.glob(".github/workflows/*.yaml")):
    lines = open(wf).read().split("\n")
    if not any(anchor.match(l) for l in lines):
        continue
    seen += 1
    if any(re.match(r"^\s*run:.*\.cicd/fleet/lag-check\.sh", l) for l in lines):
        print(f"  unchanged  {wf} (runs the lag check)")
        continue
    out = []
    for l in lines:
        out.append(l)
        m = anchor.match(l)
        if m:
            pad = " " * (len(m.group(1)) - 2)   # the step's "- name:" is two columns left of "run:"
            out += [
                "",
                f"{pad}# Every rollout of this repository's cohorts in the pinned fleet definition (.fleet/)",
                f"{pad}# has its marker in .waves/: the repository is not behind the definition it pins.",
                f"{pad}- name: Fleet rollouts applied (.fleet/ against .waves/)",
                f"{pad}  run: bash .cicd/fleet/lag-check.sh --slug {slug}",
            ]
    open(wf, "w").write("\n".join(out))
    print(f"  changed    {wf} (lag check added)")
if not seen:
    sys.exit("ERROR: no workflow in .github/workflows runs the community files check (way-a/0001-community-files)")
PY
git add .github/workflows

"${HERE}/check.sh"
