#!/usr/bin/env bash
# check.sh - is this repository already in the state way-a/0002-fleet-submodule describes?
#
# Run by the runner (wamp-cicd fleet/apply-rollout.sh) from the member repository's root, and by
# apply.sh as its last step. It changes nothing. Exit 0 = yes; 1 = no (each reason is printed).
#
# The state:
#   1. wamp-cicd is pinned AT OR AFTER the commit in rollout.toml [pins] (the .cicd submodule;
#      deps.toml in wamp-ai; wamp-cicd itself has it), and has fleet/lag-check.sh;
#   2. the shared community files match the templates of that wamp-cicd;
#   3. every workflow that runs the community files check runs the lag check as well.
# Not checked here: the definition's pin and the .waves/ markers. The runner writes them, in the
# same commit, after apply.sh and after adopting this rollout.

set -uo pipefail
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
rc=0
no() { echo "  no: $*"; rc=1; }
die() { echo "ERROR: $*" >&2; exit 1; }
# shellcheck source=/dev/null
. "${HERE}/layout.sh"
want="$(pin_of cicd)" || no "cannot read [pins] from rollout.toml"

# 1. The pin. A submodule pin is read from the index, so the answer is the same before and after
# a commit.
case "${LAYOUT}" in
    ordinary)
        have="$(git ls-files -s -- .cicd | awk '$1=="160000"{print $2}')"
        if [ -z "${have}" ]; then
            no ".cicd is not a submodule here"
        elif [ "$(git -C .cicd rev-parse --show-toplevel 2>/dev/null)" != "$(pwd)/.cicd" ] \
             || ! git -C .cicd rev-parse -q --verify "${have}^{commit}" >/dev/null 2>&1; then
            no ".cicd is not initialised in this clone (git submodule update --init .cicd)"
        elif ! git -C .cicd rev-parse -q --verify "${want}^{commit}" >/dev/null 2>&1; then
            no ".cicd is pinned to ${have:0:7}, which is before ${want:0:7} (that commit is not in its history)"
        elif ! at_or_after .cicd "${want}" "${have}"; then
            no ".cicd is pinned to ${have:0:7}, which is not at or after ${want:0:7}"
        fi ;;
    ai)
        why="$(dep_at_or_after wamp-cicd "${want}")" || no "${why}"
        for f in "${MANAGED_COPIES[@]}"; do cmp -s ".deps/wamp-cicd/${f}" "${f}" || no "${f} is not the copy of .deps/wamp-cicd/${f}"; done ;;
    cicd) ;;
esac
[ -f "${P}fleet/lag-check.sh" ] || no "no ${P}fleet/lag-check.sh"

# 2. The community files, against the templates of the pinned wamp-cicd.
if [ -f "${P}scripts/community-files.sh" ]; then
    out="$(bash "${P}scripts/community-files.sh" check . 2>&1)" || { no "the community files check fails:"; sed 's/^/      /' <<<"${out}"; }
else
    no "no ${P}scripts/community-files.sh"
fi

# 3. The lag check in CI, beside the community files check.
found=0
while IFS= read -r wf; do
    found=1
    grep -q -F "run: bash ${P}fleet/lag-check.sh" "${wf}" || no "${wf} runs the community files check but not the lag check"
done < <(grep -r -l -s -F "run: bash ${P}scripts/community-files.sh check" .github/workflows | sort)
[ "${found}" = 1 ] || no "no workflow in .github/workflows runs the community files check (way-a/0001-community-files)"

[ "${rc}" = 0 ] && echo "  yes: way-a/0002-fleet-submodule is in place (the definition's pin and .waves/ are the runner's)"
exit "${rc}"
