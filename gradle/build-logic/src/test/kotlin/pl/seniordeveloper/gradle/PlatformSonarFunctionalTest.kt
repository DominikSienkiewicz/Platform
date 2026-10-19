package pl.seniordeveloper.gradle

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.nio.file.Path

/** F-13: jedna analiza SonarQube w korzeniu, także wielomodułowego buildu. */
class PlatformSonarFunctionalTest {
	@TempDir
	lateinit var directory: Path

	@Test
	fun `a single-module consumer keeps its root sonar task and project key`() {
		val consumer = ConsumerFixture(directory, "java-library")
		consumer.appendToBuildScript(INSPECT_SONAR)

		val plan = consumer.runner("sonar", "--dry-run").build().output
		assertTrue(plan.contains(":jacocoTestReport SKIPPED") && plan.contains(":sonar SKIPPED"), "sonar must follow the coverage report")
		val properties = consumer.runner("inspectSonar").build().output
		assertTrue(properties.contains("SONAR:sonar.projectKey=DominikSienkiewicz_java-library"), "the project key must keep today's default")
	}

	@Test
	fun `a multi-module root runs one analysis over every module`() {
		val consumer = multiModuleConsumer()

		val plan = consumer.runner("sonar", "--dry-run").build().output
		assertTrue(plan.contains(":sonar SKIPPED"), "the root must own the analysis")
		listOf("a", "b").forEach { module ->
			assertTrue(plan.contains(":$module:jacocoTestReport SKIPPED"), "sonar must wait for the coverage report of :$module")
			assertFalse(plan.contains(":$module:sonar SKIPPED"), ":$module must not run its own partial analysis")
		}
		val properties = consumer.runner("inspectSonar", properties = mapOf("sonarProjectKey" to "DominikSienkiewicz_Example")).build().output
		assertTrue(properties.contains("SONAR:sonar.projectKey=DominikSienkiewicz_Example"))
		listOf("a", "b").forEach { module ->
			assertTrue(
				properties.lineSequence().any {
					it.startsWith("SONAR::$module.sonar.coverage.jacoco.xmlReportPaths=") &&
						it.endsWith("jacocoTestReport.xml")
				},
				":$module must add its own JaCoCo report to the analysis",
			)
		}
	}

	@Test
	fun `sonar conventions outside the root fail with the fix`() {
		val consumer = multiModuleConsumer()
		consumer.file("a/build.gradle.kts").appendText("\napply(plugin = \"seniordev.sonar-conventions\")\n")

		val result = consumer.runner("help").buildAndFail()
		assertTrue(result.output.contains("seniordev.sonar-conventions belongs in the root project of the build, but :a applies it"))
	}

	private fun multiModuleConsumer(): ConsumerFixture {
		val consumer = ConsumerFixture(directory, "java-library")
		val module = consumer.file("build.gradle.kts").readText()
		listOf("a", "b").forEach { name ->
			consumer.file(name).mkdirs()
			consumer.file("src").copyRecursively(consumer.file("$name/src"))
			consumer.file("$name/build.gradle.kts").writeText(module)
		}
		consumer.file("src").deleteRecursively()
		consumer.file("build.gradle.kts").writeText("plugins {\n\tbase\n\tid(\"seniordev.sonar-conventions\")\n}\n\n$INSPECT_SONAR\n")
		consumer.file("settings.gradle.kts").appendText("\ninclude(\"a\", \"b\")\n")
		return consumer
	}

	private companion object {
		// Właściwości, które SonarScanner dostałby od roota, bez wysyłania analizy.
		val INSPECT_SONAR =
			"""
			tasks.register("inspectSonar") {
			    val computed = tasks.named<org.sonarqube.gradle.SonarTask>("sonar").flatMap { it.properties }
			    doLast {
			        computed.get().filterKeys { it.endsWith("sonar.projectKey") || it.endsWith("xmlReportPaths") }
			            .forEach { (key, value) -> println("SONAR:${'$'}key=${'$'}value") }
			    }
			}
			""".trimIndent()
	}
}
