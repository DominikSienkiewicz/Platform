package pl.seniordeveloper.gradle

import java.nio.file.Path
import org.gradle.testkit.runner.TaskOutcome
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir

/**
 * Bramka pokrycia z java-conventions (`coverageMinimum`). Agregację `test` + `integrationTest` przypina
 * test Springa w [PlatformConsumerFunctionalTest]; tu są przypadki, w których bramka musi zaczerwienić build.
 */
class PlatformCoverageGateFunctionalTest {
	@TempDir
	lateinit var directory: Path

	@Test
	fun `a minimum the tests do not reach fails the gate and the effective minimum is printed`() {
		val consumer = ConsumerFixture(directory, "java-library")
		consumer.file("src/main/java/example/library/Uncovered.java").writeText(UNCOVERED_CLASS)

		val result = consumer.runner("jacocoTestCoverageVerification", properties = mapOf("coverageMinimum" to "0.99")).buildAndFail()

		assertEquals(TaskOutcome.FAILED, result.task(":jacocoTestCoverageVerification")?.outcome)
		assertTrue(result.output.contains("Rule violated"), "JaCoCo must report the violated rule")
		assertTrue(result.output.contains("Coverage gate: minimum=0.99 (source: coverageMinimum)"), "the effective minimum must be printed")
	}

	@Test
	fun `a minimum without any execution data fails check instead of skipping the gate`() {
		val consumer = ConsumerFixture(directory, "java-library")
		consumer.file("src/test").deleteRecursively()

		val result = consumer.runner("check", properties = mapOf("coverageMinimum" to "0.80")).buildAndFail()

		assertEquals(TaskOutcome.FAILED, result.task(":platformCoverageDataCheck")?.outcome)
		assertTrue(
			result.output.contains("coverageMinimum=0.80 needs JaCoCo execution data"),
			"a gate without .exec data must fail check, not end SKIPPED and green",
		)
	}

	@Test
	fun `a minimum outside 0 to 1 is rejected`() {
		val consumer = ConsumerFixture(directory, "java-library")

		val result = consumer.runner("help", properties = mapOf("coverageMinimum" to "80")).buildAndFail()

		assertTrue(result.output.contains("coverageMinimum must be a decimal between 0 and 1 (e.g. 0.80); got '80'"))
	}

	private companion object {
		const val UNCOVERED_CLASS = """package example.library;

/** Code the template's tests never reach. */
public final class Uncovered {
  private Uncovered() {}

  public static int answer() {
    return 42;
  }
}
"""
	}
}
