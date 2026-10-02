#!/usr/bin/env bash
# check.sh - is this repository already in the state way-a/0001-community-files describes?
#
# Run by the runner (wamp-cicd fleet/apply-rollout.sh) from the member repository's root, and by
# apply.sh as its last step. It changes nothing. Exit 0 = yes; 1 = no (each reason is printed).
#
# The state:
#   1. .cicd and .ai are submodules pinned AT OR AFTER the commits in rollout.toml [pins];
#   2. the shared community files match .cicd/templates/ and DEVELOPMENT.md exists
#      (`bash .cicd/scripts/community-files.sh check .`);
#   3. the justfile imports .cicd/workflow.just;
#   4. a CI workflow runs the community files check.

set -uo pipefail
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
rc=0
no() { echo "  no: $*"; rc=1; }

pin_of() { python3 - "${HERE}/rollout.toml" "$1" <<'PY'
import sys
try:
    import tomllib
except ImportError:  # Python < 3.11
    import tomli as tomllib
print(tomllib.load(open(sys.argv[1], "rb"))["pins"][sys.argv[2]])
PY
}

# 1. The pins. Read from the index, so the answer is the same before and after a commit.
for pair in .cicd:cicd .ai:ai; do
    path="${pair%%:*}"; want="$(pin_of "${pair#*:}")" || { no "cannot read [pins] from rollout.toml"; continue; }
    have="$(git ls-files -s -- "${path}" | awk '$1=="160000"{print $2}')"
    if [ -z "${have}" ]; then no "${path} is not a submodule here"; continue; fi
    if ! git -C "${path}" rev-parse -q --verify "${have}^{commit}" >/dev/null 2>&1 \
       || [ "$(git -C "${path}" rev-parse --show-toplevel 2>/dev/null)" != "$(pwd)/${path}" ]; then
        no "${path} is not initialised in this clone (git submodule update --init ${path})"; continue
    fi
    if ! git -C "${path}" rev-parse -q --verify "${want}^{commit}" >/dev/null 2>&1; then
        no "${path} is pinned to ${have:0:7}, which is before ${want:0:7} (that commit is not in its history)"
    elif ! git -C "${path}" merge-base --is-ancestor "${want}" "${have}"; then
        no "${path} is pinned to ${have:0:7}, which is not at or after ${want:0:7}"
    fi
done

# 2. The community files, against the templates of the pinned .cicd.
if [ -f .cicd/scripts/community-files.sh ]; then
    out="$(bash .cicd/scripts/community-files.sh check . 2>&1)" || { no "the community files check fails:"; sed 's/^/      /' <<<"${out}"; }
else
    no "no .cicd/scripts/community-files.sh"
fi

# 3. The Way-A workflow recipes.
grep -q -E "^import[[:space:]]+['\"]\.cicd/workflow\.just['\"]" justfile 2>/dev/null \
    || no "the justfile does not import .cicd/workflow.just"

# 4. The drift check in CI.
grep -r -q -s -E "^[[:space:]]*run:.*\.cicd/scripts/community-files\.sh check" .github/workflows \
    || no "no workflow in .github/workflows runs the community files check"

[ "${rc}" = 0 ] && echo "  yes: way-a/0001-community-files is in place"
exit "${rc}"
