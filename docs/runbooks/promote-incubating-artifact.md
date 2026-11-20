# Promote an incubating artifact

**Preconditions:** an incubating artifact (a Maven module, a private npm package or a template; Decision 7) is
ready for a first consumer.

1. In the consumer, adopt it against the unreleased change ([test an unreleased change](test-unreleased-change.md)),
   replacing the application's own configuration with what the artifact provides ([consuming.md](../consuming.md)).
2. In Platform, open the pull request that removes the *incubating* label from `docs/reference.md`,
   `docs/consuming.md` and `README.md`; for a private npm package also remove `"private": true` from its
   `package.json`.
3. Release it ([cut a release](cut-release.md)), then bump the consumer ([bump a consumer](bump-consumer.md)).

**Done when:** the consumer builds on the released artifact and no Platform document calls it incubating.
