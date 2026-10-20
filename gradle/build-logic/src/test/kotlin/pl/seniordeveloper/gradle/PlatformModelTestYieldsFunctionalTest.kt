package pl.seniordeveloper.gradle

import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.nio.file.Path

/**
 * `modelTest` konwencji ustępuje własnemu zadaniu projektu, tak jak `lint` i `format` w java-conventions. Azimuth
 * rejestruje własny `modelTest` (tag model, heap 3g pod model ONNX); konwencja rejestrowana w `plugins {}`, czyli
 * przed skryptem, zatrzymywała konfigurację komunikatem "Cannot add task 'modelTest' as a task with that name
 * already exists" (kanarek 1.6.0).
 */
class PlatformModelTestYieldsFunctionalTest {
	@TempDir
	lateinit var directory: Path

	@Test
	fun `a project's own modelTest is kept and the convention does not register a second one`() {
		val consumer = ConsumerFixture(directory, "spring-app")
		consumer.appendToBuildScript(
			"""
			tasks.register<Test>("modelTest") {
			    description = "Consumer model tests"
			    maxHeapSize = "3g"
			    useJUnitPlatform { includeTags("model") }
			}
			tasks.register("inspectModelTest") {
			    val model = tasks.named<Test>("modelTest").get()
			    val seen = "${'$'}{model.description}|${'$'}{model.maxHeapSize}"
			    doLast { println("MODEL:${'$'}seen") }
			}
			""".trimIndent(),
		)

		val build = consumer.runner("inspectModelTest").build()

		assertTrue(build.output.contains("MODEL:Consumer model tests|3g"), "the project's own modelTest must win:\n${build.output}")
		assertTrue(
			build.output.contains("defines its own modelTest task, so the Platform modelTest is not registered there"),
			"the convention must say that it kept the project's task",
		)
	}

	@Test
	fun `without a modelTest of its own the project gets the convention's task outside check`() {
		val consumer = ConsumerFixture(directory, "spring-app")
		consumer.appendToBuildScript(
			"""
			tasks.register("inspectModelTest") {
			    val model = tasks.named<Test>("modelTest").get()
			    val seen = model.description
			    doLast { println("MODEL:${'$'}seen") }
			}
			""".trimIndent(),
		)

		val build = consumer.runner("inspectModelTest").build()

		assertTrue(build.output.contains("MODEL:Runs the tests tagged model; outside check, run it on purpose."), build.output)
		assertFalse(build.output.contains("defines its own modelTest task"), "no warning without a task of the project's own")
		assertFalse(
			consumer
				.runner("check", "--dry-run")
				.build()
				.output
				.contains(":modelTest"),
			"modelTest must stay outside check",
		)
	}
}
