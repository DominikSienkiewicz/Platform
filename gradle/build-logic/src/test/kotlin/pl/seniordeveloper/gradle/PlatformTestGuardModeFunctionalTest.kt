package pl.seniordeveloper.gradle

import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.nio.file.Path

/**
 * Strażnik kontenerów z test-fixtures domyślnie failuje (N-CAP-8, faza fail z ADR-0019). Opt-out
 * `platform.test.guard=warn` ustawia się jak każde inne pokrętło Platform, właściwością Gradle'a, a konwencja
 * przekazuje ją JVM testów; bez właściwości JVM testów jej nie dostaje i obowiązuje domyślny `fail`.
 */
class PlatformTestGuardModeFunctionalTest {
	@TempDir
	lateinit var directory: Path

	@Test
	fun `the guard mode reaches the test JVM only when the build sets it`() {
		val consumer = ConsumerFixture(directory, "java-library")
		consumer.appendToBuildScript(
			"""
			tasks.register("inspectGuardMode") {
			    val mode = tasks.named<Test>("test").get().systemProperties["platform.test.guard"]
			    doLast { println("GUARD_MODE=${'$'}mode") }
			}
			""".trimIndent(),
		)

		val unset = consumer.runner("inspectGuardMode").build().output
		assertTrue(unset.contains("GUARD_MODE=null"), "without platform.test.guard the test JVM must keep the fail default:\n$unset")

		val optedOut = consumer.runner("inspectGuardMode", properties = mapOf("platform.test.guard" to "warn")).build().output
		assertTrue(optedOut.contains("GUARD_MODE=warn"), "-Pplatform.test.guard=warn must reach the test JVM:\n$optedOut")
	}
}
