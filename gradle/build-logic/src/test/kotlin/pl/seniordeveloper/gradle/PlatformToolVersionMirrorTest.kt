package pl.seniordeveloper.gradle

import java.io.File
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

/**
 * Guard luster wersji wpisanych w źródłach convention pluginów.
 *
 * Precompiled script plugin nie czyta katalogu w czasie kompilacji, więc te wersje stoją
 * w źródłach convention pluginów i w gradle/catalog jednocześnie. Rozjazd nie psuje buildu
 * Platform, a konsument dostaje wtedy wersję, której kanon nie opisuje.
 */
class PlatformToolVersionMirrorTest {

	private val javaConventions = File(System.getProperty("platform.javaConventions")).readText()
	private val springModulithConventions =
		File(System.getProperty("platform.springModulithConventions")).readText()
	private val qualityConventions = File(System.getProperty("platform.qualityConventions")).readText()
	private val workflows = File(System.getProperty("platform.workflows"))

	@Test
	fun `googleJavaFormat w java-conventions jest zgodny z kanonem katalogu`() {
		val mirrored = mirrors(javaConventions, """googleJavaFormat\("([^"]+)"\)""")

		assertEquals(listOf(canon("googleJavaFormat")), mirrored, "googleJavaFormat(...) w java-conventions musi równać się kanonowi")
	}

	@Test
	fun `toolchain w java-conventions jest zgodny z kanonem katalogu`() {
		val mirrored = mirrors(javaConventions, """JavaLanguageVersion\.of\((\d+)\)""")

		assertEquals(listOf(canon("java")), mirrored, "JavaLanguageVersion.of(...) w java-conventions musi równać się kanonowi")
	}

	@Test
	fun `nadpisanie lombok_version w spring-modulith-conventions jest zgodne z kanonem katalogu`() {
		val mirrored = mirrors(springModulithConventions, """ext\["lombok\.version"]\s*=\s*"([^"]+)"""")

		assertEquals(listOf(canon("lombok")), mirrored, "ext[\"lombok.version\"] w spring-modulith-conventions musi równać się kanonowi")
	}

	@Test
	fun `archunitVersion w spring-modulith-conventions jest zgodny z kanonem katalogu`() {
		val mirrored = mirrors(springModulithConventions, """val archunitVersion\s*=\s*"([^"]+)"""")

		assertEquals(listOf(canon("archunit")), mirrored, "archunitVersion w spring-modulith-conventions musi równać się kanonowi")
	}

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
	fun `pitestVersion w quality-conventions jest zgodny z kanonem katalogu`() {
		val mirrored = mirrors(qualityConventions, """pitestVersion\.set\("([^"]+)"\)""")

		assertEquals(listOf(canon("pitestTool")), mirrored, "pitestVersion.set(...) w quality-conventions musi równać się kanonowi")
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

	private fun mirrors(source: String, pattern: String): List<String> =
		Regex(pattern).findAll(source).map { it.groupValues[1] }.toList()

	private companion object {
		const val TOOLCHAIN_INPUT_DEFAULT = """\n {6}toolchain-java-version:(?:\n {8}[^\n]*)*?\n {8}default: "([^"]+)""""
		const val ARCHUNIT_MANAGED_EVERYWHERE =
			"""dependencyManagement\s*\{(?:[^{}]|\{[^{}]*})*?dependencies\s*\{[^{}]*?dependency\("com\.tngtech\.archunit:archunit:(\${'$'}archunitVersion)"\)"""
		val TOOLCHAIN_WORKFLOWS = listOf("backend-ci.yml", "deploy.yml", "sonar.yml")
	}
}
