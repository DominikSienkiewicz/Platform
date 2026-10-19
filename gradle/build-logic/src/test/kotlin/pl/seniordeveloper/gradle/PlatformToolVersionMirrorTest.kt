package pl.seniordeveloper.gradle

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import java.io.File

/**
 * Lustra spoza źródeł Kotlina: domyślny toolchain w reusable workflowach i struktura zarządzania ArchUnit
 * w spring-modulith-conventions. Same wersje convention pluginów pochodzą z wygenerowanego
 * PlatformVersions (PlatformVersionsTest), więc nie mają już lustra.
 */
class PlatformToolVersionMirrorTest {
	private val springModulithConventions =
		File(System.getProperty("platform.springModulithConventions")).readText()
	private val workflows = File(System.getProperty("platform.workflows"))

	@Test
	fun `spring-modulith-conventions zarzadza ArchUnit na wszystkich konfiguracjach, nie tylko testowych`() {
		val managed = mirrors(springModulithConventions, ARCHUNIT_MANAGED_EVERYWHERE)

		assertEquals(
			listOf("\$archunitVersion"),
			managed,
			"spring-modulith-core ciągnie ArchUnit 1.4.2 na runtimeClasspath (nie czyta class-file 71 z JDK 27); " +
				"dependencyManagement musi przypiąć com.tngtech.archunit:archunit do archunitVersion",
		)
	}

	@Test
	fun `domyslny toolchain-java-version w reusable workflowach jest zgodny z kanonem katalogu`() {
		val mirrored =
			workflows
				.listFiles { file -> file.name.endsWith(".yml") }
				.orEmpty()
				.sortedBy { it.name }
				.flatMap { file ->
					mirrors(file.readText(), TOOLCHAIN_INPUT_DEFAULT).map { version -> file.name to version }
				}

		assertEquals(
			TOOLCHAIN_WORKFLOWS.map { it to canon("java") },
			mirrored,
			"toolchain-java-version.default w reusable workflowach musi równać się kanonowi java",
		)
	}

	private fun canon(name: String): String = System.getProperty("platform.canon.$name")

	private fun mirrors(
		source: String,
		pattern: String,
	): List<String> = Regex(pattern).findAll(source).map { it.groupValues[1] }.toList()

	private companion object {
		const val TOOLCHAIN_INPUT_DEFAULT = """\n {6}toolchain-java-version:(?:\n {8}[^\n]*)*?\n {8}default: "([^"]+)""""
		const val ARCHUNIT_MANAGED_EVERYWHERE =
			"""dependencyManagement\s*\{(?:[^{}]|\{[^{}]*})*?dependencies\s*\{[^{}]*?dependency\("com\.tngtech\.archunit:archunit:(\${'$'}archunitVersion)"\)"""
		val TOOLCHAIN_WORKFLOWS = listOf("backend-ci.yml", "deploy.yml", "platform-bump.yml", "sonar.yml")
	}
}
