package pl.seniordeveloper.gradle

import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.nio.file.Path

class SecurityFloorResolutionFunctionalTest {
	@TempDir
	lateinit var directory: Path

	@Test
	fun `Spring dependency management resolves the published security floors`() {
		assertConsumerFloors("spring-app")
	}

	@Test
	fun `native Gradle resolves the published security floors`() {
		assertConsumerFloors("java-library", "implementation(platform(libs.platform.bom))")
	}

	private fun assertConsumerFloors(
		template: String,
		platformDependency: String = "",
	) {
		val consumer = ConsumerFixture(directory, template)
		consumer.appendToBuildScript(
			"""
			apply(plugin = "seniordev.nullness-conventions")
			dependencies {
				$platformDependency
				implementation("org.postgresql:postgresql")
				implementation("io.opentelemetry:opentelemetry-sdk")
				implementation("ch.qos.logback:logback-classic")
			}
			tasks.register("showSecurityFloors") {
				val selected = listOf("runtimeClasspath", "checkstyle", "annotationProcessor").flatMap { scope ->
					configurations.getByName(scope).incoming.resolutionResult.allComponents
						.mapNotNull { it.moduleVersion }.map { scope + "=" + it }
				}
				inputs.property("selected", selected)
				doLast { selected.forEach { println(it) } }
			}
			""".trimIndent(),
		)

		val output = consumer.runner("showSecurityFloors").build().output.lines()
		mapOf(
			"runtimeClasspath=org.postgresql:postgresql" to "postgresqlJdbc",
			"runtimeClasspath=io.opentelemetry:opentelemetry-sdk" to "openTelemetry",
			"runtimeClasspath=ch.qos.logback:logback-classic" to "logback",
			"runtimeClasspath=ch.qos.logback:logback-core" to "logback",
			"checkstyle=com.google.guava:guava" to "guava",
			"annotationProcessor=com.google.guava:guava" to "guava",
		).forEach { (module, key) ->
			val expected = "$module:${System.getProperty("platform.canon.$key")}"
			assertTrue(expected in output, "Expected $expected in $output")
		}
	}
}
