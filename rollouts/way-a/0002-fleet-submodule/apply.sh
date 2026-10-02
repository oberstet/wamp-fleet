#!/usr/bin/env bash
# apply.sh - bring a repository into the state way-a/0002-fleet-submodule describes.
#
# Run by the runner (wamp-cicd fleet/apply-rollout.sh) from the member repository's root, on the
# rollout branch, with a clean tree. It changes files and stages them; it never commits, pushes or
# talks to a forge, and needs no credentials. Re-runnable: a second run changes nothing.
#
# What it does:
#   1. wamp-cicd and wamp-ai at the commits in rollout.toml [pins] (never moved backwards) - their
#      heads as of this rollout, the same pair in every member:
#        an ordinary member   the .cicd and .ai submodules
#        wamp-ai              wamp-cicd in deps.toml / .deps/, and the managed copies refreshed
#        wamp-cicd            wamp-ai in deps.toml / .deps/
#   2. the shared community files, re-deployed from the templates of that wamp-cicd;
#   3. the lag check as a CI step, directly after the community files check, in every workflow
#      that runs it.
# What it does NOT do: the definition's pin (the .fleet submodule; deps.toml in a tooling source)
# and the .waves/ markers. The runner writes those, in the same commit, for every rollout.

set -euo pipefail
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
: "${FLEET_DEF_DIR:?run by the runner (wamp-cicd fleet/apply-rollout.sh)}" "${FLEET_SLUG:?}"
die() { echo "ERROR: $*" >&2; exit 1; }
# shellcheck source=/dev/null
. "${HERE}/layout.sh"

# 1. The pins.
case "${LAYOUT}" in
    ordinary)
        [ -e .cicd/.git ] || die ".cicd is not initialised in this clone (git submodule update --init .cicd)"
        set_pin .cicd "${CICD_URL}" "$(pin_of cicd)"
        set_pin .ai   "${AI_URL}"   "$(pin_of ai)" ;;
    ai)
        set_dep wamp-cicd "${CICD_URL}" "$(pin_of cicd)" .cicd
        for f in "${MANAGED_COPIES[@]}"; do
            cmp -s ".deps/wamp-cicd/${f}" "${f}" || { mkdir -p "$(dirname "${f}")"; cp -p ".deps/wamp-cicd/${f}" "${f}"; echo "  deployed   ${f} (a managed copy from .deps/wamp-cicd)"; }
            git add "${f}"
        done ;;
    cicd)
        set_dep wamp-ai "${AI_URL}" "$(pin_of ai)" .ai ;;
esac
[ -f "${P}fleet/lag-check.sh" ] || die "no ${P}fleet/lag-check.sh"

# 2. The community files: the copies must match the templates of the wamp-cicd just pinned.
bash "${P}scripts/community-files.sh" deploy . | sed '$d'
git add -A -- CONTRIBUTING.md DEVELOPMENT.md .audit/README.md .github

# 3. The lag check in CI. The slug is written out: a fork's own CI would otherwise look itself up
# in the inventory under the fork's name. The definition needs no argument: the check uses
# .fleet/ where there is one, else the definition under .deps/.
python3 - "${FLEET_SLUG}" "${P}" <<'PY'
import glob, re, sys
slug, p = sys.argv[1], sys.argv[2]
anchor = re.compile(r"^(\s*)run: bash " + re.escape(p) + r"scripts/community-files\.sh check")
lag = "run: bash " + p + "fleet/lag-check.sh"
seen = 0
for wf in sorted(glob.glob(".github/workflows/*.yml") + glob.glob(".github/workflows/*.yaml")):
    lines = open(wf).read().split("\n")
    if not any(anchor.match(l) for l in lines):
        continue
    seen += 1
    if any(l.strip().startswith(lag) for l in lines):
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
                f"{pad}# Every rollout of this repository's cohorts in the pinned fleet definition has its",
                f"{pad}# marker in .waves/: the repository is not behind the definition it pins.",
                f"{pad}- name: Fleet rollouts applied (the pinned definition against .waves/)",
                f"{pad}  {lag} --slug {slug}",
            ]
    open(wf, "w").write("\n".join(out))
    print(f"  changed    {wf} (lag check added)")
if not seen:
    sys.exit("ERROR: no workflow in .github/workflows runs the community files check (way-a/0001-community-files)")
PY
git add .github/workflows

"${HERE}/check.sh"
