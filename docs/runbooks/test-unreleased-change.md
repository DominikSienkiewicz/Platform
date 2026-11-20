# Test an unreleased Platform change

**Preconditions:** the Platform change is committed on a branch, and the consumer checkout sits next to Platform.
`-PplatformRepository` is the only official way (Decision 6): never copy a convention plugin or a config into the
consumer.

1. In Platform: `./buildAndPublishLocal.sh` publishes to `~/.m2/repository`.
2. In the consumer: build with `-PplatformRepository=file://$HOME/.m2/repository`
   ([local development](../local-development.md)).

**Done when:** the consumer build is green against the locally published Platform.
