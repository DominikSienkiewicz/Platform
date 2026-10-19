package pl.seniordeveloper.gradle

import org.gradle.testkit.runner.BuildResult
import org.gradle.testkit.runner.TaskOutcome
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.nio.file.Path

/**
 * N-DX-3: backend wyrenderowany przez scripts/new-consumer.sh — a nie kopia startera — przechodzi `lint test`
 * na opublikowanych konwencjach. Generator i startery nie mogą się więc rozjechać bez czerwonego testu.
 */
class GeneratedConsumerFunctionalTest {
	@TempDir
	lateinit var directory: Path

	@Test
	fun `a generated spring-app consumer passes lint and test`() {
		assertLintAndTestPass(generate("spring-app"))
	}

	@Test
	fun `a generated java-library consumer passes lint and test`() {
		assertLintAndTestPass(generate("java-library"))
	}

	private fun generate(kind: String): Path {
		val out = directory.resolve("generated-$kind")
		val generator = Path.of(System.getProperty("platform.templates")).resolve("../../scripts/new-consumer.sh").normalize()
		val process =
			ProcessBuilder(
				"bash",
				generator.toString(),
				"--name",
				"generated-$kind",
				"--package",
				"pl.example.generated",
				"--kind",
				kind,
				"--out",
				out.toString(),
				"--platform-version",
				System.getProperty("platform.version"),
			).redirectErrorStream(true).start()
		val output = process.inputStream.bufferedReader().readText()
		assertEquals(0, process.waitFor(), "new-consumer.sh failed:\n$output")
		return out.resolve("backend")
	}

	private fun assertLintAndTestPass(backend: Path) {
		val result: BuildResult = ConsumerFixture.existing(backend).runner("lint", "test").build()
		listOf(":lint", ":spotlessCheck", ":platformDependencyCheck", ":platformPinCheck", ":test").forEach { path ->
			val outcome = result.task(path)?.outcome
			assertTrue(
				outcome in setOf(TaskOutcome.SUCCESS, TaskOutcome.UP_TO_DATE),
				"$path must run on the generated consumer, but its outcome was $outcome",
			)
		}
	}
}
