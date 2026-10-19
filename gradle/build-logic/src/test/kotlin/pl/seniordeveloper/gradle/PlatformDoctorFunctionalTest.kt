package pl.seniordeveloper.gradle

import org.gradle.testkit.runner.TaskOutcome
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.nio.file.Path

/** platformDoctor na starterze java-library: piny, toolchain i coverageMinimum pod configuration cache. */
class PlatformDoctorFunctionalTest {
	@TempDir
	lateinit var directory: Path

	private val version = System.getProperty("platform.version")

	@Test
	fun `the starter passes and the second run reuses the configuration cache`() {
		val consumer = ConsumerFixture(directory, "java-library")

		val first = consumer.runner("platformDoctor", "--configuration-cache").build()
		val second = consumer.runner("platformDoctor", "--configuration-cache").build()

		assertEquals(TaskOutcome.SUCCESS, first.task(":platformDoctor")?.outcome)
		assertTrue(
			first.output.contains("PASS PD080 seniordev.settings-conventions, platform-catalog, platformVersion are all $version"),
			"the pins must be compared",
		)
		assertTrue(first.output.contains("PASS PD081 the Java 27 toolchain resolves to "), "the toolchain must resolve")
		assertTrue(first.output.contains("WARN PD082 coverageMinimum is not set"), "an unset coverageMinimum must warn")
		assertTrue(second.output.contains("Reusing configuration cache"), "platformDoctor must be configuration-cache compatible")
	}

	@Test
	fun `a catalog pinned apart from the settings plugin fails with PD080`() {
		val consumer = ConsumerFixture(directory, "java-library")
		val settings = consumer.file("settings.gradle.kts")
		settings.writeText(
			settings.readLines().joinToString("\n") { line ->
				if ("platform-catalog:" in line) "$line\n\t\t\tversion(\"platform\", \"1.0.0\")" else line
			},
		)

		val result = consumer.runner("platformDoctor").buildAndFail()

		assertEquals(TaskOutcome.FAILED, result.task(":platformDoctor")?.outcome)
		assertTrue(
			result.output.contains(
				"FAIL PD080 the Gradle-side Platform pins disagree: seniordev.settings-conventions $version, " +
					"platform-catalog 1.0.0, platformVersion $version",
			),
			"the diverging pin must be named",
		)
		assertTrue(result.output.contains("1 platformDoctor check(s) failed"), "only PD080 may fail")
	}
}
