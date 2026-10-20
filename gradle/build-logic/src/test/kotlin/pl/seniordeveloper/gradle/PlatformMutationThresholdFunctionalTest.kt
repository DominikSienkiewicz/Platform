package pl.seniordeveloper.gradle

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.nio.file.Path

/** Próg siły mutacji PIT: ułamek 0..1 z bloku `platform` albo właściwości `platform.mutation.threshold`, bez nich bez progu. */
class PlatformMutationThresholdFunctionalTest {
	@TempDir
	lateinit var directory: Path

	private val inspectThreshold =
		"""
		tasks.register("inspectMutationThreshold") {
		    val threshold = pitest.mutationThreshold.map { it.toString() }.orElse("unset")
		    doLast { println("MUTATION:${'$'}{threshold.get()}") }
		}
		""".trimIndent()

	private fun threshold(output: String): String = output.lineSequence().single { it.startsWith("MUTATION:") }

	@Test
	fun `without a threshold PIT keeps its own default`() {
		val consumer = ConsumerFixture(directory, "java-library")
		consumer.appendToBuildScript(inspectThreshold)

		val result = consumer.runner("inspectMutationThreshold").build()
		assertEquals("MUTATION:unset", threshold(result.output))
	}

	@Test
	fun `the platform block sets the PIT threshold as a percentage`() {
		val consumer = ConsumerFixture(directory, "java-library")
		consumer.appendToBuildScript("platform {\n    mutation { threshold.set(\"0.65\".toBigDecimal()) }\n}\n$inspectThreshold")

		val result = consumer.runner("inspectMutationThreshold", properties = mapOf("platform.mutation.threshold" to "0.10")).build()
		assertEquals("MUTATION:65", threshold(result.output), "the platform block must win over platform.mutation.threshold")
	}

	@Test
	fun `the threshold property sets the threshold without the block`() {
		val consumer = ConsumerFixture(directory, "java-library")
		consumer.appendToBuildScript(inspectThreshold)

		val result = consumer.runner("inspectMutationThreshold", properties = mapOf("platform.mutation.threshold" to "0.805")).build()
		assertEquals("MUTATION:81", threshold(result.output), "a fraction between two percents rounds up, never down")
	}

	@Test
	fun `a threshold outside 0 to 1 fails with its gate code`() {
		val property = ConsumerFixture(directory.resolve("property"), "java-library")
		property.appendToBuildScript(inspectThreshold)
		val fromProperty = property.runner("inspectMutationThreshold", properties = mapOf("platform.mutation.threshold" to "80")).buildAndFail()
		assertTrue(
			fromProperty.output.contains("[PLAT-MUT-001] platform.mutation.threshold must be a decimal between 0 and 1 (e.g. 0.60); got '80'"),
		)

		val block = ConsumerFixture(directory.resolve("block"), "java-library")
		block.appendToBuildScript("platform {\n    mutation { threshold.set(\"1.5\".toBigDecimal()) }\n}\n$inspectThreshold")
		val fromBlock = block.runner("inspectMutationThreshold").buildAndFail()
		assertTrue(fromBlock.output.contains("[PLAT-MUT-001] platform { mutation { threshold } } must be a decimal between 0 and 1"))
	}
}
