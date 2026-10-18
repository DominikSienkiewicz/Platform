package pl.seniordeveloper.gradle

import java.nio.file.Path
import org.gradle.testkit.runner.TaskOutcome
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir

/**
 * Konsument może podstawić wersję do BOM-ów Platform przez właściwość `*.version`, której platformDependencyCheck
 * nie widzi. Decyzja 18: platformBomOverrideCheck ostrzega z listą, build zostaje zielony, a własne nadpisania
 * Platform (lombok, tomcat, jackson) nie są zgłaszane.
 */
class PlatformBomOverrideFunctionalTest {
	@TempDir
	lateinit var directory: Path

	@Test
	fun `a consumer BOM property override is reported, the build stays green`() {
		val consumer = ConsumerFixture(directory, "spring-app")
		consumer.appendToBuildScript("""extra["jackson-bom.version"] = "3.0.0"""")

		val result = consumer.runner("platformBomOverrideCheck").build()

		assertEquals(TaskOutcome.SUCCESS, result.task(":platformBomOverrideCheck")?.outcome)
		assertTrue(result.output.contains("platformBomOverrideCheck: jackson-bom.version=3.0.0 overrides the Platform BOMs"), result.output)
		listOf("lombok.version", "tomcat.version", "jackson-2-bom.version").forEach { owned ->
			assertFalse(result.output.contains("platformBomOverrideCheck: $owned="), "Platform's own $owned must not be reported")
		}
	}

	@Test
	fun `a consumer without overrides passes quietly`() {
		val result = ConsumerFixture(directory, "spring-app").runner("platformBomOverrideCheck").build()

		assertTrue(result.output.contains("platformBomOverrideCheck: OK"), result.output)
	}
}
