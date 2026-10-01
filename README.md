# wamp-fleet

The definition of the **`wamp` fleet**: the implementation-neutral WAMP ground: the protocol specification and the shared tooling. It records which repositories belong to
the fleet, in which cohorts, and the rollouts applied to them.

The tools that read this repository are in
[wamp-proto/wamp-cicd `fleet/`](https://github.com/wamp-proto/wamp-cicd/tree/main/fleet)
(pinned here as `.cicd/`); this repository holds only the definition.

## Terms

- **Fleet** — all the repositories managed together. Every repository belongs to exactly one fleet.
- **Cohort** — a named subset of the fleet. A repository may be in several, or in none (then it
  takes part in nothing).
- **Rollout** — one batched change applied to one cohort: a desired state, and how to reach it.
  Once applied it is not edited; a change is a new rollout.
- **Wave** — one run of a rollout on its cohort. A member the wave has not reached yet is simply
  behind; it does not change cohorts.

## What is here

| path | what |
|---|---|
| [`fleet.toml`](fleet.toml) | the inventory: the cohorts, and every repository with its GitHub slug, default branch and cohorts. **Generated - do not edit by hand.** |
| [`rollouts/<cohort>/<NNNN>-<name>/`](rollouts/) | one directory per rollout, in order. The ordered list of a cohort's rollouts **is** this directory. |
| `.ai/`, `.cicd/` | the shared AI policy and CI/CD tooling, as in every repository of the fleet. The `.cicd/` pin is the tools version this fleet's rollouts are written against. |
| `.audit/` | the AI-assistance disclosure per branch. |

This repository is not a member of its own fleet: it cannot contain itself.

### The inventory

```toml
schema = 2
[[cohort]]   name, description
[[repo]]     name, slug, default_branch, cohorts = [...]
```

The contract is `.cicd/fleet/lib/check-inventory.py`; CI runs it on every pull request, and
locally:

```bash
just check-inventory
just check-rollouts      # every rollouts/<cohort>/<NNNN>-<name>/ is a valid rollout
```

`fleet.toml` is generated from the maintainers' inventory and committed here. To change the
fleet's membership or cohorts, change it there and regenerate; a hand edit would be overwritten.

### A rollout

```
rollouts/<cohort>/<NNNN>-<name>/
    rollout.toml     what it does, and what "applied" means
    apply.sh         makes the change in a member repository, on the rollout branch; re-runnable;
                     needs no credentials; never commits
    check.sh         changes nothing; exit 0 if the repository already is in the rollout's state
    issue.md         the text of the rollout issue filed in each repository
```

`<NNNN>` orders the rollouts of a cohort, and nothing is skipped: a member gets them in order.
A rollout is applied to one member by the runner, wamp-cicd's `fleet/apply-rollout.sh`: it runs
`apply.sh`, pins this repository in the member as `.fleet/`, writes the marker
`.waves/<cohort>/<NNNN>-<name>.toml`, and makes one commit. An earlier rollout without a marker is
**adopted** (its marker written) when its `check.sh` passes. Once a marker anywhere names a
rollout, the rollout is not edited any more.

| rollout | what |
|---|---|
| [`way-a/0001-community-files`](rollouts/way-a/0001-community-files/) | the shared tooling pins, the shared contribution files, the Way-A workflow. Applied by hand on 2026-09-29 where the record in its `rollout.toml` says so, and adopted there; applied by `apply.sh` elsewhere. |
| [`way-a/0002-fleet-submodule`](rollouts/way-a/0002-fleet-submodule/) | `.fleet/` and `.waves/` in every member, and the CI check that fails when a member lacks a rollout its pinned definition holds. |

Who is behind, per repository and cohort: `just -f .cicd/fleet/fleet.just fleet-next`.

## Using it

On a machine with a clone of wamp-cicd and of this repository:

```bash
mkdir -p ~/.config/wamp-cicd/fleet && chmod 700 ~/.config/wamp-cicd/fleet
ln -s "$PWD/fleet.toml" ~/.config/wamp-cicd/fleet/wamp.toml
FLEET_NAME=wamp just -f <wamp-cicd>/fleet/fleet.just fleet-check
```

and then the recipes described in wamp-cicd's
[`fleet/README.md`](https://github.com/wamp-proto/wamp-cicd/blob/main/fleet/README.md):
`fleet-where`, `fleet-next`, `fleet-rollout init <name> --cohort <cohort> --rollout <NNNN>-<name>`, ...

## Contributing

See [CONTRIBUTING.md](https://github.com/wamp-proto/wamp-cicd/blob/main/templates/CONTRIBUTING.md):
GitHub issue first, then a branch, with the AI-assistance disclosure in `.audit/`.
