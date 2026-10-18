# ADR-0010: Opt-in agent resource profile via AI_AGENT

## Status

Accepted — 2026-10-19

## Context

The consumer repositories are developed largely by coding agents, often several at once on one
machine. Every layer of the stack sizes itself for a machine it owns alone: Gradle workers and test
forks, the JVM heap, cached Spring test contexts with their connection pools, and Vitest workers all
default to the host's core count or memory. Several agents multiply that default.

On 2026-07-27 the maintainer measured this on the development machine:

- one agent running a consumer's Spring integration tests used about 4.3 GB;
- the machine stayed responsive with at most six agents at once, of which at most three ran a JVM
  integration-test task at the same time;
- beyond that the machine ran out of memory before it ran out of cores: the load average rose while
  the CPU sat mostly idle, waiting for memory pages.

A suite that fails only under that load is starved, not broken; asynchronous assertions with default
timeouts fail first.

## Decision

- Platform ships a resource profile that only an explicit `AI_AGENT=1` or `AI_AGENT=true` turns on.
  Any other value, an absent variable, and `CI` alone leave the ordinary defaults, so a human in a
  terminal and every CI run behave as before.
- With the profile, `seniordev.java-conventions` gives every Java test task one fork, a 2 GiB maximum
  heap and at most four cached Spring contexts (`spring.test.context.cache.maxSize=4`), and a shared
  build service (`AgentTestBudget`) lets only one test task run at a time within a build.
- `templates/agent-gradle.sh` adds `--max-workers=2 --no-parallel` before Gradle starts, because a
  settings plugin cannot resize services Gradle has already created. `@dominiksienkiewicz/vitest-config`
  caps Vitest at two workers.
- The profile bounds one build. It does not coordinate separate Gradle invocations or agents; the
  number of agents is the harness's decision, made before it dispatches them.

## Consequences

- An agent's test run takes longer, and in exchange several agents can run on one machine without
  starving each other into timeouts.
- The numbers belong to one machine and one date. Re-measure them on other hardware, and when a
  change of the stack (a new JDK, Testcontainers or Spring Boot) moves the memory per agent.
- The switch lives in a public plugin, so its existence and rationale are public; the machine and its
  process inventory are not part of this record.

## Revisit when

The memory per agent changes noticeably, or the agents move to dedicated Linux build machines, where
containers run without a virtual machine and the interactive desktop's memory is not shared.
