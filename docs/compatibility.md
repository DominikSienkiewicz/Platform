# Compatibility matrix

Which Java, Gradle, Spring and frontend versions each Platform release brings. A consumer that pins a
release reads its row; a maintainer who bumps a toolchain, a BOM or Gradle adds one.

<!-- compatibility-matrix -->
| Platform | Released | Java toolchain | Runtime image | JDK running Gradle | Gradle minimum | Gradle tested | Spring Boot | Spring Modulith | Spring AI | Node | Next.js | pnpm (Platform) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1.6.0 | 2026-10-20 | 27 | `sapmachine:27-jre` | 25 | 9.6.1 | 9.8.1 | 4.1.1 | 2.1.1 | 2.0.1 | >=22.13 | 16.4.0 | 11.18.0 |
| 1.5.31 | 2026-10-14 | 27 | `sapmachine:27-jre` | 25 | not declared | 9.8.1 | 4.1.1 | 2.1.1 | 2.0.1 | not declared | 16.4.0 | 11.18.0 |
| 1.5.29 | 2026-09-25 | 27 | `sapmachine:27-jre` | 25 | not declared | 9.6.1 | 4.1.0 | 2.1.0 | 2.0.0 | not declared | 16.3.0 | 11.18.0 |
| 1.5.0 | never published | 26 | `eclipse-temurin:25-jre` ¹ | 25 | not declared | 9.6.1 | 4.1.0 | 2.1.0 | 2.0.0 | not declared | 16.2.7 | 9.15.0 |
| 1.4.0 | 2026-07-01 | 26 | `eclipse-temurin:25-jre` ¹ | 25 | not declared | 9.5.1 | 4.1.0 | 2.1.0 | 2.0.0 | not declared | 16.2.7 | 9.15.0 |

¹ The runtime image ran an older Java than the toolchain, so an application built from that release
stopped at startup with `UnsupportedClassVersionError`. Releases from 1.6.0 on fail `check` on such
a Dockerfile (`platformRuntimeImageCheck`).

## Columns

- **Java toolchain**: the bytecode consumers compile to, catalog entry `java`.
- **Runtime image**: the final `FROM` of [`templates/Dockerfile.backend`](../templates/Dockerfile.backend).
- **JDK running Gradle**: the JDK `backend-ci.yml` runs Gradle on; Platform's build-logic is compiled
  for it. From 1.8.0 it equals the Java toolchain, one JDK for everything
  ([ADR-0034](adr/0034-one-jdk-27-for-gradle-build-logic-and-toolchain.md)), and the Gradle minimum is the
  first Gradle that starts on it.
- **Gradle minimum**: the oldest Gradle the settings plugin accepts and TestKit builds a consumer on.
  **Gradle tested**: Platform's own wrappers and the version `platform-bump` gives a consumer.
- **Spring Boot, Spring Modulith, Spring AI**: the BOMs `seniordev.spring-modulith-conventions`
  imports.
- **Node**: the `engines.node` of the published npm packages. **Next.js**: the canon in
  `@dominiksienkiewicz/versions`. **pnpm**: what Platform builds its own packages with; consumers
  use npm ([ADR-0006](adr/0006-pnpm-in-platform-npm-in-consumers.md)).

The reusable workflows have no column of their own: a consumer calls them at the tag of its pin, so
the workflows of a row are the ones of that release.

## Maintaining the table

The top row describes `main`. When a change moves a value in it, the change edits the top row, and the
release then keeps it as that version's row; the next change of a value adds a new top row.
`CompatibilityMatrixTest` in `gradle/build-logic` fails when the top row disagrees with the catalog,
the Dockerfile template, the Gradle minimum, the frontend canon or the workspace manifest. Older rows
are history and nothing checks them; releases between the listed ones were not backfilled.
