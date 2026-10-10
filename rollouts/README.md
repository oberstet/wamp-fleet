<!-- Generated at each rollout close-out, from the
     rollout.toml records in this directory. Do not edit: it is rewritten. -->

# Rollouts

One record per rollout, newest first. Each `rollout.toml` records the aspect and its
revision, the inventory commit the members were read from, and per member the issue,
the commit that applied the change, the maintainer's land merge and the convergence
proof.

| rollout | aspect | status | fleet issue | members | changes | aspect rev |
|---|---|---|---|---|---|---|
| [`20261010-way-a`](20261010-way-a/rollout.toml) | `way-a` | converged | [#14](https://github.com/wamp-proto/wamp-fleet/issues/14) | [wamp-proto#579](https://github.com/wamp-proto/wamp-proto/issues/579), [wamp-cicd#80](https://github.com/wamp-proto/wamp-cicd/issues/80), [wamp-ai#35](https://github.com/wamp-proto/wamp-ai/issues/35), [wamp-site-gen#6](https://github.com/wamp-proto/wamp-site-gen/issues/6), [wamp-fleet#13](https://github.com/wamp-proto/wamp-fleet/issues/13) | `.ai`, `.cicd`, `aspects.toml`, `deps.toml` | `fb2604d2c` |
