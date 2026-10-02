Repo:  @@SLUG@@
Title: [CI/CD] Fleet rollout way-a/0002-fleet-submodule: pin the fleet definition, record rollouts (.waves/), lag check in CI
Type:  CI/CD

---

## Summary

This repository's part of the fleet rollout **`way-a/0002-fleet-submodule`**, applied to every
member of the `way-a` cohort of the `wamp` fleet: @@FLEET_LIST@@. The rollout is defined in
[wamp-proto/wamp-fleet](https://github.com/wamp-proto/wamp-fleet/tree/main/rollouts/way-a/0002-fleet-submodule)
and applied by the runner in wamp-proto/wamp-cicd (`fleet/apply-rollout.sh`), one issue and one
branch per repository.

From this rollout on, a fleet-wide change is a **migration**: a script in the fleet's definition
repository, applied to each member the same way, and recorded in the member itself.

## Changes

1. **The fleet's definition repository (wamp-proto/wamp-fleet), pinned**: as the new submodule
   `.fleet/`. It holds the inventory (`fleet.toml`) and the ordered rollouts of each cohort.
2. **`.waves/<cohort>/<NNNN>-<name>.toml`**: one marker per rollout this repository has received
   (which definition commit, which script, which issue, when). Where
   `way-a/0001-community-files` was applied by hand in September, its marker is written here too,
   after its check passes.
3. **wamp-proto/wamp-cicd pinned at `8465a48`** (`.cicd`): the version of the shared tooling with
   the lag check (and with `just land` for branches that change the tooling pins, and the audit
   file that `just new-branch` no longer forgets). The shared community files are re-deployed
   from its templates.
4. **Lag check in CI**: a step directly after the community files check,
   `fleet/lag-check.sh --slug @@SLUG@@` from the pinned wamp-cicd. It fails when a rollout of
   this repository's cohorts in the pinned definition has no marker in `.waves/`: a repository
   cannot silently fall behind the definition it pins.

**In wamp-proto/wamp-cicd and wamp-proto/wamp-ai** - the two repositories every other one pins,
which therefore carry no submodules
([TOOLING-STRUCTURE.md](https://github.com/wamp-proto/wamp-cicd/blob/main/TOOLING-STRUCTURE.md)) -
the same pins are entries in `deps.toml`, checked out into the gitignored `.deps/` by `just deps`,
instead of submodules. Everything else is the same.

No behaviour change in the software itself.

## Acceptance criteria

- [ ] The definition is pinned at a commit of wamp-proto/wamp-fleet's `main` (`.fleet`; or
      `deps.toml`).
- [ ] `.waves/way-a/0001-community-files.toml` and `.waves/way-a/0002-fleet-submodule.toml` exist.
- [ ] wamp-cicd is pinned at `8465a48` or later; the community files check passes.
- [ ] The lag check passes locally and in CI.
- [ ] `just where` works.
- [ ] CI green; landed as a maintainer-signed change.

Note: This issue was drafted with AI assistance (Claude Code).
