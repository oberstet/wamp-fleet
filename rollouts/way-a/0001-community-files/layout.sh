# layout.sh - sourced by apply.sh and check.sh: which layout is this repository in, and how a pin
# is set in it. (The same file in every rollout of this cohort that moves a tooling pin.)
#
# An ordinary member pins wamp-cicd, wamp-ai and the fleet definition as submodules. The two
# TOOLING SOURCES - wamp-cicd and wamp-ai, which every other repository pins - carry no
# submodules: their dependencies are pinned in deps.toml and checked out into the gitignored
# .deps/ (wamp-cicd: TOOLING-STRUCTURE.md, scripts/deps.sh). The runner says which it is:
#
#   FLEET_TOOLING_SOURCE   ""       an ordinary member
#                          .cicd    wamp-cicd itself
#                          .ai      wamp-ai itself
#
# Set here:
#   P        prefix of everything that comes from wamp-cicd:  .cicd/ | "" | .deps/wamp-cicd/
#   LAYOUT   ordinary | cicd | ai

CICD_URL="https://github.com/wamp-proto/wamp-cicd.git"
AI_URL="https://github.com/wamp-proto/wamp-ai.git"

case "${FLEET_TOOLING_SOURCE:-}" in
    "")    LAYOUT=ordinary; P=".cicd/" ;;
    .cicd) LAYOUT=cicd;     P="" ;;
    .ai)   LAYOUT=ai;       P=".deps/wamp-cicd/" ;;
    *)     echo "ERROR: unknown FLEET_TOOLING_SOURCE '${FLEET_TOOLING_SOURCE}'" >&2; exit 1 ;;
esac

# pin_of <key> [<table>]: a commit from rollout.toml - [pins] by default, [pins.tooling] for the
# tooling sources where it differs.
pin_of() { python3 - "${HERE}/rollout.toml" "$@" <<'PY'
import sys
try:
    import tomllib
except ImportError:  # Python < 3.11
    import tomli as tomllib
pins = tomllib.load(open(sys.argv[1], "rb"))["pins"]
table = pins.get(sys.argv[3], {}) if len(sys.argv) > 3 else pins
print(table.get(sys.argv[2]) or pins[sys.argv[2]])
PY
}

# The deps.sh to use in a tooling source: its own (wamp-cicd has it; wamp-ai carries a managed
# copy), else the runner's - which is what brings the copy in the first place.
deps_sh() {
    if [ -f scripts/deps.sh ]; then echo scripts/deps.sh
    else echo "${FLEET_TOOLS_DIR:?}/../scripts/deps.sh"; fi
}

# at_or_after <git dir> <want> <have>: is <have> the commit <want> or a later one?
at_or_after() { git -C "$1" merge-base --is-ancestor "$2" "$3" 2>/dev/null; }

# set_pin <path> <forge url> <commit>: <path> is a SUBMODULE at <commit>, or later if it already
# is. Objects come from the definition clone's own checkout of the same submodule when it has one
# (no network), else from the forge. .gitmodules records the forge URL either way.
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
    elif at_or_after "${path}" "${want}" "${have}"; then
        echo "  kept       ${path} at ${have:0:7} (at or after ${want:0:7})"
    elif at_or_after "${path}" "${have}" "${want}"; then
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

# set_dep <name> <forge url> <commit> <submodule path in the definition clone>: in a tooling
# source, deps.toml pins <name> at <commit>, or later if it already does, and .deps/<name> is
# that checkout. Objects from the definition clone's submodule checkout when it has one.
set_dep() {
    local name="$1" url="$2" want="$3" src="${FLEET_DEF_DIR}/$4" d=".deps/$1" have from=() deps
    deps="$(deps_sh)"
    [ ! -e "${src}/.git" ] || from=(--from "${name}=${src}")
    git check-ignore -q .deps/x 2>/dev/null || { echo ".deps/" >> .gitignore; git add .gitignore; }
    have="$(bash "${deps}" get "${name}" 2>/dev/null | cut -d' ' -f1 || true)"
    if [ -z "${have}" ]; then
        bash "${deps}" set "${name}" "${url}" "${want}" >/dev/null && bash "${deps}" sync "${from[@]}" "${name}" >/dev/null \
            || die "could not pin ${name} at ${want:0:7}"
        echo "  added      ${d} at ${want:0:7} (deps.toml)"
    else
        bash "${deps}" sync "${from[@]}" "${name}" >/dev/null || die "could not check out ${d} at ${have:0:7}"
        git -C "${d}" rev-parse -q --verify "${want}^{commit}" >/dev/null 2>&1 \
            || { [ ${#from[@]} -eq 0 ] || git -C "${d}" -c protocol.file.allow=always fetch --quiet "${src}" HEAD 2>/dev/null || true; }
        git -C "${d}" rev-parse -q --verify "${want}^{commit}" >/dev/null 2>&1 \
            || git -C "${d}" fetch --quiet origin 2>/dev/null || true
        git -C "${d}" rev-parse -q --verify "${want}^{commit}" >/dev/null 2>&1 || die "${d}: cannot get commit ${want}"
        if at_or_after "${d}" "${want}" "${have}"; then
            echo "  kept       ${d} at ${have:0:7} (at or after ${want:0:7})"
        elif at_or_after "${d}" "${have}" "${want}"; then
            bash "${deps}" set "${name}" "${url}" "${want}" >/dev/null && bash "${deps}" sync "${from[@]}" "${name}" >/dev/null \
                || die "could not move ${name} to ${want:0:7}"
            echo "  pinned     ${d} ${have:0:7} -> ${want:0:7} (deps.toml)"
        else
            die "${d} is at ${have:0:7}, which is neither before nor after ${want:0:7}"
        fi
    fi
    git add deps.toml
}

# dep_at_or_after <name> <commit>: for check.sh - prints a reason and returns 1 if not.
dep_at_or_after() {
    local name="$1" want="$2" d=".deps/$1" have
    have="$(bash "$(deps_sh)" get "${name}" 2>/dev/null | cut -d' ' -f1 || true)"
    [ -n "${have}" ] || { echo "deps.toml does not pin ${name}"; return 1; }
    [ "$(git -C "${d}" rev-parse -q --verify HEAD 2>/dev/null)" = "${have}" ] \
        || { echo "${d} is not checked out at the pin ${have:0:7} (just deps)"; return 1; }
    git -C "${d}" rev-parse -q --verify "${want}^{commit}" >/dev/null 2>&1 \
        || { echo "${name} is pinned at ${have:0:7}, which is before ${want:0:7} (that commit is not in its history)"; return 1; }
    at_or_after "${d}" "${want}" "${have}" || { echo "${name} is pinned at ${have:0:7}, which is not at or after ${want:0:7}"; return 1; }
}

# managed_copy <file>: in wamp-ai, <file> is a byte-identical copy of the one in .deps/wamp-cicd.
MANAGED_COPIES=(scripts/deps.sh TOOLING-STRUCTURE.md)
