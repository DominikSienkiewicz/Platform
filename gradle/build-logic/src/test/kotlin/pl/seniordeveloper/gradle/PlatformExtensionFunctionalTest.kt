package pl.seniordeveloper.gradle

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.nio.file.Path

/** Typowany blok `platform { }` (N-DX-15): wygrywa z właściwościami, a bez niego działają jak dotąd. */
class PlatformExtensionFunctionalTest {
	@TempDir
	lateinit var directory: Path

	@Test
	fun `the platform block sets the effective coverage threshold`() {
		val consumer = ConsumerFixture(directory, "java-library")
		consumer.appendToBuildScript("platform {\n    coverage { minimum.set(\"0.5\".toBigDecimal()) }\n}")

		val result = consumer.runner("jacocoTestCoverageVerification", properties = mapOf("coverageMinimum" to "0.99")).build()
		assertTrue(
			result.output.contains("Coverage gate: minimum=0.5 (source: platform.coverage.minimum)"),
			"the platform block must win over coverageMinimum and say so",
		)
	}

	@Test
	fun `a threshold outside 0 to 1 names the platform block`() {
		val consumer = ConsumerFixture(directory, "java-library")
		consumer.appendToBuildScript("platform {\n    coverage { minimum.set(\"80\".toBigDecimal()) }\n}")

		val result = consumer.runner("jacocoTestCoverageVerification").buildAndFail()
		assertTrue(result.output.contains("[PLAT-COV-002] platform.coverage.minimum must be a decimal between 0 and 1"))
	}

	@Test
	fun `mutation targets and static analysis map onto PIT and SpotBugs`() {
		val consumer = ConsumerFixture(directory, "java-library")
		consumer.appendToBuildScript(
			"""
			platform {
			    mutation { targetPackages.add("example.library") }
			    staticAnalysis { failOnBugs.set(true) }
			}
			tasks.register("inspectPlatform") {
			    val targets = pitest.targetClasses
			    val ignore = spotbugs.ignoreFailures
			    doLast { println("PLATFORM:${'$'}{targets.get()}:${'$'}{ignore.get()}") }
			}
			""".trimIndent(),
		)
		val result = consumer.runner("inspectPlatform").build()
		assertEquals("PLATFORM:[example.library.*]:false", result.output.lineSequence().single { it.startsWith("PLATFORM:") })
	}

	@Test
	fun `without the block the defaults stay`() {
		val consumer = ConsumerFixture(directory, "java-library")
		consumer.appendToBuildScript(
			"""
			tasks.register("inspectPlatform") {
			    val targets = pitest.targetClasses.map { it.toString() }.orElse("unset")
			    val ignore = spotbugs.ignoreFailures
			    doLast { println("PLATFORM:${'$'}{targets.get()}:${'$'}{ignore.get()}") }
			}
			""".trimIndent(),
		)
		val result = consumer.runner("inspectPlatform", "jacocoTestCoverageVerification", properties = mapOf("coverageMinimum" to "0.10")).build()
		assertEquals("PLATFORM:unset:true", result.output.lineSequence().single { it.startsWith("PLATFORM:") })
		assertTrue(result.output.contains("Coverage gate: minimum=0.10 (source: coverageMinimum)"))
	}
}
