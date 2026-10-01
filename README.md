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
```

`fleet.toml` is generated from the maintainers' inventory and committed here. To change the
fleet's membership or cohorts, change it there and regenerate; a hand edit would be overwritten.

### A rollout

```
rollouts/<cohort>/<NNNN>-<name>/
    rollout.toml     what it does, and what "applied" means
    apply.sh         makes the change in a member repository, on the rollout branch; re-runnable;
                     needs no credentials
    issue.md         the text of the rollout issue filed in each repository
```

`<NNNN>` orders the rollouts of a cohort. The first one,
[`way-a/0001-community-files`](rollouts/way-a/0001-community-files/), is the record of the
rollout that brought the shared contribution workflow (applied by hand on 2026-09-29, so it has no
`apply.sh`). wamp-site-gen, wamp-ai and wamp-cicd are members of `way-a` that this rollout has not reached yet.

## Using it

On a machine with a clone of wamp-cicd and of this repository:

```bash
mkdir -p ~/.config/wamp-cicd/fleet && chmod 700 ~/.config/wamp-cicd/fleet
ln -s "$PWD/fleet.toml" ~/.config/wamp-cicd/fleet/wamp.toml
FLEET_NAME=wamp just -f <wamp-cicd>/fleet/fleet.just fleet-check
```

and then the recipes described in wamp-cicd's
[`fleet/README.md`](https://github.com/wamp-proto/wamp-cicd/blob/main/fleet/README.md):
`fleet-where`, `fleet-rollout init <name> --cohort <cohort> --issue-template <rollout>/issue.md`, ...

## Contributing

See [CONTRIBUTING.md](https://github.com/wamp-proto/wamp-cicd/blob/main/templates/CONTRIBUTING.md):
GitHub issue first, then a branch, with the AI-assistance disclosure in `.audit/`.
