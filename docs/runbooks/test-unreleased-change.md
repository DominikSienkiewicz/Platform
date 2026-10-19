# Test an unreleased Platform change

**Preconditions:** the Platform change is committed on a branch, and the consumer checkout sits next to Platform.
`-PplatformRepository` is the only official way (Decision 6): never copy a convention plugin or a config into the
consumer.

1. In Platform: `scripts/preview-on-consumer.sh ../<consumer>` runs the fast lane (compile and
   `platformDependencyCheck`) of the consumer against the change; add `--frontend` for the frontend canon and
   `--gradle "<tasks>"` for other tasks.
2. Before a release, `scripts/canary.sh` runs the same preview on every consumer of `scripts/consumers.txt` and
   records the result for `HEAD`, which `./release.sh` requires.
3. For a manual run, `./buildAndPublishLocal.sh` publishes to `~/.m2/repository`; the consumer then builds with
   `-PplatformRepository=file://$HOME/.m2/repository` ([local development](../local-development.md)).

**Done when:** `scripts/canary.sh` ends with PASS for every consumer.
