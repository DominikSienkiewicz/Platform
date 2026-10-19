# Integration tests ran, and their coverage was thrown away

**Symptom.** Consumers with Spring Modulith had adapters covered only by Testcontainers integration tests,
and those adapters reported 0% coverage. SonarCloud showed a project figure several points lower than what
the tests actually exercised.

**Root cause.** `seniordev.spring-modulith-conventions` splits tests into `test` and `integrationTest`.
JaCoCo's `jacocoTestReport` reads only `test.exec` by default, so the execution data of `integrationTest`
was written and never read: the Docker time was spent, the coverage discarded.

**Fix.** [`seniordev.java-conventions`](../../gradle/build-logic/src/main/kotlin/seniordev.java-conventions.gradle.kts)
sums the execution data of `test` and `integrationTest`, binding them by name because `integrationTest` is
registered by a later plugin. `modelTest` stays out of the sum, so the local figure and the CI figure are
the same number. The report and the gate hang on `check`, not on `test`, so a plain `./gradlew test` does not
start Testcontainers.

**Guards.** `platformCoverageDataCheck` fails `check` when a coverage threshold is set and no test task
produced data, so a module cannot pass the gate by skipping its tests. TestKit covers both:
[`PlatformCoverageGateFunctionalTest`](../../gradle/build-logic/src/test/kotlin/pl/seniordeveloper/gradle/PlatformCoverageGateFunctionalTest.kt).
