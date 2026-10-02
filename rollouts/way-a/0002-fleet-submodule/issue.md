Repo:  @@SLUG@@
Title: [CI/CD] Fleet rollout way-a/0002-fleet-submodule: pin the fleet definition (.fleet), record rollouts (.waves/), lag check in CI
Type:  CI/CD

---

## Summary

This repository's part of the fleet rollout **`way-a/0002-fleet-submodule`**, applied to every
member of the `way-a` cohort of the `wamp` fleet: @@FLEET_LIST@@. The rollout is defined in
[wamp-proto/wamp-fleet](https://github.com/wamp-proto/wamp-fleet/tree/main/rollouts/way-a/0002-fleet-submodule)
and applied by the runner in wamp-proto/wamp-cicd (`fleet/apply-rollout.sh`, wamp-proto/wamp-cicd#64),
one issue and one branch per repository.

From this rollout on, a fleet-wide change is a **migration**: a script in the fleet's definition
repository, applied to each member the same way, and recorded in the member itself.

## Changes

1. **`.fleet/`**: a new submodule, the fleet's definition repository (wamp-proto/wamp-fleet),
   pinned. It holds the inventory (`fleet.toml`) and the ordered rollouts of each cohort.
2. **`.waves/<cohort>/<NNNN>-<name>.toml`**: one marker per rollout this repository has received
   (which definition commit, which script, which issue, when). This rollout writes two: its own,
   and the one for `way-a/0001-community-files`, which was applied by hand in September and is
   adopted here after its check passes.
3. **`.cicd` → wamp-proto/wamp-cicd @ `d9c45e5`**: the first version of the shared tooling with the
   lag check (and with `just land` for branches that change the tooling pins, and the audit file
   that `just new-branch` no longer forgets). The shared community files are re-deployed from its
   templates.
4. **Lag check in CI**: a step directly after the community files check,
   `bash .cicd/fleet/lag-check.sh --slug @@SLUG@@`. It fails when a rollout of this repository's
   cohorts in the pinned `.fleet/` has no marker in `.waves/`: a repository cannot silently fall
   behind the definition it pins.

No behaviour change in the software itself.

## Acceptance criteria

- [ ] `.fleet` is a submodule at a commit of wamp-proto/wamp-fleet's `main`.
- [ ] `.waves/way-a/0001-community-files.toml` and `.waves/way-a/0002-fleet-submodule.toml` exist.
- [ ] `.cicd` is pinned at `d9c45e5` or later; the community files check passes.
- [ ] `bash .cicd/fleet/lag-check.sh --slug @@SLUG@@` passes locally and in CI.
- [ ] `just where` works.
- [ ] CI green; landed as a maintainer-signed change.

Note: This issue was drafted with AI assistance (Claude Code).
