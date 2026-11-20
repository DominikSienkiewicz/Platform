package pl.seniordeveloper.gradle

import org.gradle.testkit.runner.TaskOutcome
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.nio.file.Path

/**
 * Negatywne przypadki platformDependencyCheck — bramki governance wpiętej w `check` u wszystkich konsumentów.
 * Bramka zbiera wszystkie naruszenia w jeden wyjątek, więc przypadki są pogrupowane w cztery przebiegi TestKit.
 */
class PlatformDependencyCheckFunctionalTest {
	@TempDir
	lateinit var directory: Path

	@Test
	fun `explicit versions that differ from the canon fail with an actionable message`() {
		val consumer = ConsumerFixture(directory, "java-library")
		consumer.appendToBuildScript(
			"""
			dependencies {
			    implementation("org.jspecify:jspecify:0.3.0")
			    implementation(platform("org.springframework.boot:spring-boot-dependencies:4.0.0"))
			    testImplementation("org.jspecify:jspecify") { version { strictly("0.2.0") } }
			}
			""".trimIndent(),
		)

		val output = failedCheck(consumer)

		assertViolation(
			output,
			"org.jspecify:jspecify:0.3.0 (implementation) — Platform canon is ${canon("jspecify")}: declare it as libs.jspecify",
		)
		assertViolation(
			output,
			"org.jspecify:jspecify:0.2.0 (testImplementation) — Platform canon is ${canon("jspecify")}: declare it as libs.jspecify",
		)
		assertViolation(
			output,
			"org.springframework.boot:spring-boot-dependencies:4.0.0 (implementation) — Platform canon is ${canon(
				"springBoot",
			)}: declare it as libs.spring.boot.bom",
		)
	}

	@Test
	fun `an explicit version outside the canon passes`() {
		val consumer = ConsumerFixture(directory, "java-library")
		consumer.appendToBuildScript("""dependencies { implementation("com.example:unknown:1.0") }""")

		val result = consumer.runner("platformDependencyCheck").build()

		assertEquals(TaskOutcome.SUCCESS, result.task(":platformDependencyCheck")?.outcome)
	}

	@Test
	fun `constraints, custom source sets and Platform artifacts are governed`() {
		val consumer = ConsumerFixture(directory, "java-library")
		consumer.appendToBuildScript(
			"""
			sourceSets.create("extra")
			dependencies {
			    constraints { implementation("org.jspecify:jspecify:0.3.0") }
			    "extraImplementation"("org.jspecify:jspecify:0.3.0")
			    testImplementation("pl.seniordeveloper:platform-test-fixtures:1.4.3")
			}
			""".trimIndent(),
		)

		val output = failedCheck(consumer)

		assertViolation(
			output,
			"org.jspecify:jspecify:0.3.0 (implementation constraint) — Platform canon is ${canon("jspecify")}: declare it as libs.jspecify",
		)
		assertViolation(
			output,
			"org.jspecify:jspecify:0.3.0 (extraImplementation) — Platform canon is ${canon("jspecify")}: declare it as libs.jspecify",
		)
		assertViolation(
			output,
			"pl.seniordeveloper:platform-test-fixtures:1.4.3 (testImplementation) — Platform canon is ${System.getProperty(
				"platform.version",
			)}: declare it as libs.platform.test.fixtures",
		)
	}

	@Test
	fun `Spring buckets are governed and BOM-managed starters are told to drop the version`() {
		val consumer = ConsumerFixture(directory, "spring-app")
		consumer.appendToBuildScript(
			"""
			dependencies {
			    developmentOnly("org.jspecify:jspecify:0.2.0")
			    implementation("org.springframework.boot:spring-boot-starter-webmvc:4.0.0")
			    implementation("org.springframework.boot:spring-boot-starter-mail:4.0.0")
			}
			""".trimIndent(),
		)

		val output = failedCheck(consumer)

		assertViolation(
			output,
			"org.jspecify:jspecify:0.2.0 (developmentOnly) — Platform canon is ${canon("jspecify")}: declare it as libs.jspecify",
		)
		assertViolation(
			output,
			"org.springframework.boot:spring-boot-starter-webmvc:4.0.0 (implementation) — managed by the Platform BOMs: remove the explicit version and declare it as libs.boot.starter.webmvc",
		)
		assertViolation(
			output,
			"org.springframework.boot:spring-boot-starter-mail:4.0.0 (implementation) — the Platform BOMs manage it at " +
				"${canon("springBoot")}: remove the explicit version. To run another version on purpose, override the BOM " +
				"property instead, which platformBomOverrideCheck reports",
		)
	}

	private fun failedCheck(consumer: ConsumerFixture): String {
		val result = consumer.runner("platformDependencyCheck").buildAndFail()
		assertEquals(TaskOutcome.FAILED, result.task(":platformDependencyCheck")?.outcome)
		assertTrue(result.output.contains("Dependency versions outside the Platform canon"), "missing the governance header")
		return result.output
	}

	private fun assertViolation(
		output: String,
		violation: String,
	) {
		assertTrue(output.contains(violation), "platformDependencyCheck must report:\n  $violation")
	}

	private fun canon(name: String): String = System.getProperty("platform.canon.$name")
}
