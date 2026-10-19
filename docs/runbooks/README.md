# Runbooks

Step-by-step procedures that span Platform and its consumers. Each lists its preconditions, numbered commands and
a check that proves it is done. `templates/tests/agent-docs.test.sh` fails when a command, task, bin or path
named here no longer exists.

| Runbook | Where it runs |
|---|---|
| [Bump a consumer](bump-consumer.md) | consumer |
| [Add a JVM library](add-jvm-library.md) | Platform, then consumer |
| [Add a frontend dependency](add-frontend-dependency.md) | Platform, then consumer |
| [Test an unreleased Platform change](test-unreleased-change.md) | Platform and consumer, locally |
| [Promote an incubating artifact](promote-incubating-artifact.md) | consumer, then Platform |
| [Cut a Platform release](cut-release.md) | Platform |
| [Roll back a bad Platform release](rollback.md) | Platform, then consumer |
