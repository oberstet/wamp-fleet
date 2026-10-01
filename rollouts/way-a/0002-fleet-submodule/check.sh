#!/usr/bin/env bash
# check.sh - is this repository already in the state way-a/0002-fleet-submodule describes?
#
# Run by the runner (wamp-cicd fleet/apply-rollout.sh) from the member repository's root, and by
# apply.sh as its last step. It changes nothing. Exit 0 = yes; 1 = no (each reason is printed).
#
# The state:
#   1. .cicd is pinned AT OR AFTER the commit in rollout.toml [pins], and has fleet/lag-check.sh;
#   2. the shared community files match the templates of that .cicd;
#   3. every workflow that runs the community files check runs the lag check as well.
# Not checked here: the .fleet submodule and the .waves/ markers. The runner writes them, in the
# same commit, after apply.sh and after adopting this rollout.

set -uo pipefail
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
rc=0
no() { echo "  no: $*"; rc=1; }

want="$(python3 - "${HERE}/rollout.toml" <<'PY'
import sys
try:
    import tomllib
except ImportError:  # Python < 3.11
    import tomli as tomllib
print(tomllib.load(open(sys.argv[1], "rb"))["pins"]["cicd"])
PY
)" || no "cannot read [pins] from rollout.toml"

# 1. The pin. Read from the index, so the answer is the same before and after a commit.
have="$(git ls-files -s -- .cicd | awk '$1=="160000"{print $2}')"
if [ -z "${have}" ]; then
    no ".cicd is not a submodule here"
elif [ "$(git -C .cicd rev-parse --show-toplevel 2>/dev/null)" != "$(pwd)/.cicd" ] \
     || ! git -C .cicd rev-parse -q --verify "${have}^{commit}" >/dev/null 2>&1; then
    no ".cicd is not initialised in this clone (git submodule update --init .cicd)"
elif ! git -C .cicd rev-parse -q --verify "${want}^{commit}" >/dev/null 2>&1; then
    no ".cicd is pinned to ${have:0:7}, which is before ${want:0:7} (that commit is not in its history)"
elif ! git -C .cicd merge-base --is-ancestor "${want}" "${have}"; then
    no ".cicd is pinned to ${have:0:7}, which is not at or after ${want:0:7}"
fi
[ -f .cicd/fleet/lag-check.sh ] || no "no .cicd/fleet/lag-check.sh"

# 2. The community files, against the templates of the pinned .cicd.
if [ -f .cicd/scripts/community-files.sh ]; then
    out="$(bash .cicd/scripts/community-files.sh check . 2>&1)" || { no "the community files check fails:"; sed 's/^/      /' <<<"${out}"; }
else
    no "no .cicd/scripts/community-files.sh"
fi

# 3. The lag check in CI, beside the community files check.
found=0
while IFS= read -r wf; do
    found=1
    grep -q -E "^[[:space:]]*run:.*\.cicd/fleet/lag-check\.sh" "${wf}" || no "${wf} runs the community files check but not the lag check"
done < <(grep -r -l -s -E "^[[:space:]]*run:.*\.cicd/scripts/community-files\.sh check" .github/workflows | sort)
[ "${found}" = 1 ] || no "no workflow in .github/workflows runs the community files check (way-a/0001-community-files)"

[ "${rc}" = 0 ] && echo "  yes: way-a/0002-fleet-submodule is in place (.fleet and .waves/ are the runner's)"
exit "${rc}"
