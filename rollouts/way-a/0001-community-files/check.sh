#!/usr/bin/env bash
# check.sh - is this repository already in the state way-a/0001-community-files describes?
#
# Run by the runner (wamp-cicd fleet/apply-rollout.sh) from the member repository's root, and by
# apply.sh as its last step. It changes nothing. Exit 0 = yes; 1 = no (each reason is printed).
#
# The state:
#   1. the tooling is pinned AT OR AFTER the commits in rollout.toml:
#        an ordinary member   .cicd and .ai, as submodules
#        wamp-cicd            wamp-ai in deps.toml / .deps/; CLAUDE.md and AI_POLICY.md there
#        wamp-ai              wamp-cicd in deps.toml / .deps/; the managed copies identical
#   2. the shared community files match wamp-cicd's templates and DEVELOPMENT.md exists;
#   3. the justfile imports workflow.just;
#   4. a CI workflow runs the community files check.

set -uo pipefail
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
rc=0
no() { echo "  no: $*"; rc=1; }
die() { echo "ERROR: $*" >&2; exit 1; }
# shellcheck source=/dev/null
. "${HERE}/layout.sh"

# 1. The pins. Submodule pins are read from the index, so the answer is the same before and
# after a commit.
sub_at_or_after() {  # sub_at_or_after <path> <commit>
    local path="$1" want="$2" have
    have="$(git ls-files -s -- "${path}" | awk '$1=="160000"{print $2}')"
    if [ -z "${have}" ]; then no "${path} is not a submodule here"; return; fi
    if ! git -C "${path}" rev-parse -q --verify "${have}^{commit}" >/dev/null 2>&1 \
       || [ "$(git -C "${path}" rev-parse --show-toplevel 2>/dev/null)" != "$(pwd)/${path}" ]; then
        no "${path} is not initialised in this clone (git submodule update --init ${path})"; return
    fi
    if ! git -C "${path}" rev-parse -q --verify "${want}^{commit}" >/dev/null 2>&1; then
        no "${path} is pinned to ${have:0:7}, which is before ${want:0:7} (that commit is not in its history)"
    elif ! at_or_after "${path}" "${want}" "${have}"; then
        no "${path} is pinned to ${have:0:7}, which is not at or after ${want:0:7}"
    fi
}
case "${LAYOUT}" in
    ordinary)
        sub_at_or_after .cicd "$(pin_of cicd)"
        sub_at_or_after .ai   "$(pin_of ai)" ;;
    cicd)
        why="$(dep_at_or_after wamp-ai "$(pin_of ai tooling)")" || no "${why}"
        for f in CLAUDE.md AI_POLICY.md; do [ -e "${f}" ] || [ -L "${f}" ] || no "no ${f} (a link into .deps/wamp-ai)"; done ;;
    ai)
        why="$(dep_at_or_after wamp-cicd "$(pin_of cicd tooling)")" || no "${why}"
        for f in "${MANAGED_COPIES[@]}"; do cmp -s ".deps/wamp-cicd/${f}" "${f}" || no "${f} is not the copy of .deps/wamp-cicd/${f}"; done ;;
esac
[ "${LAYOUT}" = ordinary ] || [ -z "$(git ls-files -s | awk '$1=="160000"')" ] || no "a tooling source must carry no submodules"

# 2. The community files, against the templates of the pinned wamp-cicd.
if [ -f "${P}scripts/community-files.sh" ]; then
    out="$(bash "${P}scripts/community-files.sh" check . 2>&1)" || { no "the community files check fails:"; sed 's/^/      /' <<<"${out}"; }
else
    no "no ${P}scripts/community-files.sh"
fi

# 3. The Way-A workflow recipes.
case "${LAYOUT}" in
    ordinary) imp="import[[:space:]]+['\"]\.cicd/workflow\.just['\"]" ;;
    cicd)     imp="import[[:space:]]+['\"]workflow\.just['\"]" ;;
    ai)       imp="import\??[[:space:]]+['\"]\.deps/wamp-cicd/workflow\.just['\"]" ;;
esac
grep -q -E "^${imp}" justfile 2>/dev/null || no "the justfile does not import workflow.just"

# 4. The drift check in CI.
grep -r -q -s -F "run: bash ${P}scripts/community-files.sh check" .github/workflows \
    || no "no workflow in .github/workflows runs the community files check"

[ "${rc}" = 0 ] && echo "  yes: way-a/0001-community-files is in place"
exit "${rc}"
