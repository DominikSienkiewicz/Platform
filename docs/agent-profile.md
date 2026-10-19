# Agent resource profile

Coding agents run many builds in parallel on one machine, and every layer of the stack sizes itself for the
whole host. The agent profile bounds what one agent takes. It is opt-in: the agent harness sets
`AI_AGENT=1` or `AI_AGENT=true`, while a person in a terminal and CI keep the defaults
([ADR-0010](adr/0010-agent-resource-profile.md)). Any other value, `0` and `false` included, leaves it off.

## Contract

| Knob | Where | Default in agent mode | Without `AI_AGENT` | Effect | Stack |
|---|---|---|---|---|---|
| `AI_AGENT` | environment | — | off | turns the profile on | all |
| `platform.agent.testForks` | `-P` or `gradle.properties` | `1` | Gradle's default | `maxParallelForks` of every test task | Gradle |
| `platform.agent.testHeap` | `-P` or `gradle.properties` | `2g` | Gradle's default | `maxHeapSize` of every test task | Gradle |
| `springContextCacheSize` | `-P` or `gradle.properties` | `4` | Spring's default (32) | `spring.test.context.cache.maxSize` of every test task; an ADR-0007 exception, because Azimuth already sets this name | Gradle, Spring tests |
| `AI_AGENT_MAX_WORKERS` | environment | `2` | Gradle's and Vitest's defaults | `--max-workers` of `scripts/agent-gradle.sh` and `test.maxWorkers` of the Vitest preset | Gradle, Vitest |
| `AI_AGENT_TEST_SLOTS` | environment | `3` | no slots | how many test suites `scripts/agent-gradle.sh` runs at once on the machine | Gradle |
| `AI_AGENT_SLOT_TIMEOUT` | environment | `3600` | — | seconds `scripts/agent-gradle.sh` waits for a slot before exiting with 75 | Gradle |

An explicit Gradle property applies in every mode; agent mode only changes the defaults. So a repository
that needs more heap for one suite sets `platform.agent.testHeap=3g` in `gradle.properties` instead of
forking the logic. In agent mode `seniordev.java-conventions` also lets one test task run at a time across
the projects of a build (a shared build service), and logs one line per build, so the transcript shows the
budget that applied:

```text
Platform agent profile: testForks=1 testHeap=2g springContextCache=4 (AI_AGENT=1)
```

## Gradle invocations

Copy [`templates/agent-gradle.sh`](../templates/agent-gradle.sh) to `scripts/agent-gradle.sh` and run
`AI_AGENT=1 bash scripts/agent-gradle.sh <tasks>`. It runs `./gradlew` from the repository root, or
`backend/gradlew` from `backend/` when the root has no wrapper, and adds
`--max-workers=$AI_AGENT_MAX_WORKERS --no-parallel`. A run of `test`, `integrationTest`, `check` or `build`
first takes one of `AI_AGENT_TEST_SLOTS` machine-wide slots, so parallel agents never run more test suites at
once. Slots live under `$TMPDIR`, so agents in separate containers are not coordinated. A value of
`AI_AGENT_MAX_WORKERS` that is not a positive integer exits with 2. Without `AI_AGENT` the launcher passes
the arguments through unchanged.

## Before dispatching agents

[`templates/agent-preflight.sh`](../templates/agent-preflight.sh) answers how many agents the machine
holds right now, from free memory and swap on macOS or Linux. It exits 0 to go, 1 to reduce concurrency to
the number it prints and 2 to stop. Its defaults (4.3 GB per agent, a 6 GB reserve, at most 3) were measured
on one host; set `AGENT_COST_GB`, `AGENT_RESERVE_GB` and `AGENT_MAX` for yours.

## Vitest

`@dominiksienkiewicz/vitest-config` sets `test.maxWorkers` to `AI_AGENT_MAX_WORKERS` (default 2) in agent
mode. The value is read when the configuration module loads; an invalid one fails the import with its value.
`CI` alone does not enable the profile, and a consumer's own `test.maxWorkers`, merged after `baseConfig`,
still wins.
