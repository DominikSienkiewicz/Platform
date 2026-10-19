package pl.seniordeveloper.gradle

import org.gradle.testkit.runner.TaskOutcome
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.nio.file.Path

/** platformPinCheck na starterze java-library: katalog przypięty obok settings pluginu wywala `lint` z obiema wersjami. */
class PlatformPinCheckFunctionalTest {
	@TempDir
	lateinit var directory: Path

	private val version = System.getProperty("platform.version")

	@Test
	fun `matching pins pass`() {
		val result = ConsumerFixture(directory, "java-library").runner("platformPinCheck").build()

		assertEquals(TaskOutcome.SUCCESS, result.task(":platformPinCheck")?.outcome)
		assertTrue(result.output.contains("platformPinCheck: OK — the settings plugin and platform-catalog are both $version"))
	}

	@Test
	fun `a catalog pinned apart from the settings plugin fails lint with both versions`() {
		val consumer = ConsumerFixture(directory, "java-library")
		val settings = consumer.file("settings.gradle.kts")
		settings.writeText(
			settings.readLines().joinToString("\n") { line ->
				if ("platform-catalog:" in line) "$line\n\t\t\tversion(\"platform\", \"0.0.0\")" else line
			},
		)

		val result = consumer.runner("lint").buildAndFail()

		val message = PlatformPinCheck.mismatch(version, "0.0.0")
		assertEquals(TaskOutcome.FAILED, result.task(":platformPinCheck")?.outcome)
		assertTrue(result.output.contains(message), "platformPinCheck must name both pins and the fix")
		assertTrue(
			result.output.indexOf(message) < result.output.indexOf("> Task :platformPinCheck"),
			"the cause must be logged at configuration time",
		)
	}
}
