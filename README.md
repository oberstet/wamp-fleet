# wamp-fleet

The definition of the **`wamp` fleet**: the implementation-neutral WAMP ground: the protocol specification and the shared tooling. It records which repositories belong to
the fleet, in which cohorts, and the rollouts applied to them.

The tools that read this repository are in
[wamp-proto/wamp-cicd `fleet/`](https://github.com/wamp-proto/wamp-cicd/tree/main/fleet)
(pinned here as `.cicd/`); this repository holds only the definition. The rollout records under
`rollouts/` are written by the fleet driver (the AAIARE Fleet Manager).

## Terms

- **Fleet** — all the repositories managed together. Every repository belongs to exactly one fleet.
- **Cohort** — a named subset of the fleet. A repository may be in several, or in none (then it
  takes part in nothing).
- **Aspect** — a desired state of a repository, defined once in the fleet's aspect repository
  (e.g. `python-package`). A member declares the aspects it has in its `aspects.toml`.
- **Rollout** — one aspect applied to the members that declare it, recorded in one file. Once
  landed the record is not edited; a change is a new rollout.

## What is here

| path | what |
|---|---|
| [`fleet.toml`](fleet.toml) | the inventory: the cohorts, and every repository with its GitHub slug, default branch and cohorts. **Generated - do not edit by hand.** |
| `rollouts/<id>/rollout.toml` | one record per rollout, `<id>` = `YYYYMMDD-<aspect>[-N]`. |
| `.ai/`, `.cicd/` | the shared AI policy and CI/CD tooling, as in every repository of the fleet. |
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
rollouts/<id>/rollout.toml      <id> = YYYYMMDD-<aspect>[-N]
```

The record says what was rolled out, from which inputs, and how it went:

- the aspect, the revision of the aspect repository it was computed with, and the commit of the
  maintainers' inventory the member set was read from;
- per member: the base commit, the files changed and the exact change (with its sha256), the
  issue and its branch (`fix_<issue>`), the commit that applied the change, the maintainer's land
  merge, and a **convergence proof** - the aspect re-checked on the default branch after the land
  (an empty change = converged);
- the fleet issue that tracked the rollout, and its status:
  `planned` -> `issues-filed` -> `executed` -> `landed` -> `converged`.

The fleet driver writes it as the rollout moves through its human gates - filing the issues,
cutting the branches, landing - which a maintainer does and signs. While the rollout runs the
record lives on this repository's dev branch; it is landed here once the rollout is converged.

No rollout has been recorded in this fleet yet. The v1 rollouts (`rollouts/way-a/`, scripts
applied by a runner) are in the Git history before #11.

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
