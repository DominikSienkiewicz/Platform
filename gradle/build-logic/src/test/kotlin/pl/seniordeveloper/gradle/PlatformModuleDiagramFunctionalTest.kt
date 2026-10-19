package pl.seniordeveloper.gradle

import org.gradle.testkit.runner.TaskOutcome
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.nio.file.Path

/**
 * N-CAP-14: diagram modułów w README (blok mermaid włączany z docs/diagrams/spring-app-modules.mmd) to bajt w bajt
 * plik modules.mmd, który AbstractModulithDocumentationTest z opublikowanych test-fixtures pisze dla startera
 * spring-app. Zmiana modułów startera albo generatora bez nowego pliku wzorcowego = czerwony test.
 */
class PlatformModuleDiagramFunctionalTest {
	@TempDir
	lateinit var directory: Path

	@Test
	fun `the documentation test of the spring-app starter writes the Mermaid diagram the README shows`() {
		val consumer = ConsumerFixture(directory, "spring-app")

		val result = consumer.runner("test").build()

		assertEquals(TaskOutcome.SUCCESS, result.task(":test")?.outcome)
		val committed = File(System.getProperty("platform.templates"), "../../docs/diagrams/spring-app-modules.mmd")
		assertEquals(
			committed.readText(),
			consumer.file("build/spring-modulith-docs/modules.mmd").readText(),
			"docs/diagrams/spring-app-modules.mmd must equal the diagram the starter generates: copy " +
				"build/spring-modulith-docs/modules.mmd of templates/jvm/spring-app there and run scripts/docs-gen.sh",
		)
	}
}
