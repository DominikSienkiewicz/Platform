package pl.seniordeveloper.gradle

import java.io.File
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

/**
 * Guard luster, których nie obejmuje [PlatformToolVersionMirrorTest]: wersje BOM-ów Spring i JUnit
 * w spring-modulith-conventions, toolVersion Checkstyle/JaCoCo w java-conventions oraz SpotBugs
 * i pitest-junit5 w quality-conventions.
 *
 * Rozjazd BOM-u jest dla konsumenta cichy: platformDependencyCheck nie widzi importów mavenBom(...),
 * więc runtime zostaje na starym BOM-ie razem z jego poprawkami CVE. Pełna tabela luster: docs/versions.md.
 */
class PlatformCatalogMirrorTest {

	private val javaConventions = File(System.getProperty("platform.javaConventions")).readText()
	private val springModulithConventions =
		File(System.getProperty("platform.springModulithConventions")).readText()
	private val qualityConventions = File(System.getProperty("platform.qualityConventions")).readText()

	@Test
	fun `springBootVersion in spring-modulith-conventions matches the catalog`() {
		assertMirror(springModulithConventions, valLiteral("springBootVersion"), "springBoot", "springBootVersion in spring-modulith-conventions")
	}

	@Test
	fun `springModulithVersion in spring-modulith-conventions matches the catalog`() {
		assertMirror(springModulithConventions, valLiteral("springModulithVersion"), "springModulith", "springModulithVersion in spring-modulith-conventions")
	}

	@Test
	fun `springAiVersion in spring-modulith-conventions matches the catalog`() {
		assertMirror(springModulithConventions, valLiteral("springAiVersion"), "springAi", "springAiVersion in spring-modulith-conventions")
	}

	@Test
	fun `junitVersion in spring-modulith-conventions matches the catalog`() {
		assertMirror(springModulithConventions, valLiteral("junitVersion"), "junit", "junitVersion in spring-modulith-conventions")
	}

	@Test
	fun `checkstyle and jacoco toolVersion in java-conventions match the catalog in source order`() {
		val mirrored = mirrors(javaConventions, """toolVersion\s*=\s*"([^"]+)"""")

		assertEquals(
			listOf(canon("checkstyle"), canon("jacoco")),
			mirrored,
			"toolVersion in java-conventions (checkstyle { … }, then jacoco { … }) must equal catalog entries checkstyle and jacoco",
		)
	}

	@Test
	fun `spotbugs toolVersion in quality-conventions matches the catalog`() {
		assertMirror(qualityConventions, """toolVersion\.set\("([^"]+)"\)""", "spotbugs", "spotbugs toolVersion in quality-conventions")
	}

	@Test
	fun `junit5PluginVersion in quality-conventions matches the catalog`() {
		assertMirror(qualityConventions, """junit5PluginVersion\.set\("([^"]+)"\)""", "pitestJunit5", "junit5PluginVersion in quality-conventions")
	}

	private fun assertMirror(source: String, pattern: String, catalogKey: String, mirror: String) {
		assertEquals(listOf(canon(catalogKey)), mirrors(source, pattern), "$mirror must equal catalog entry $catalogKey")
	}

	private fun valLiteral(name: String): String = """val $name\s*=\s*"([^"]+)""""

	private fun canon(name: String): String =
		checkNotNull(System.getProperty("platform.canon.$name")) { "build-logic test task does not pass platform.canon.$name" }

	private fun mirrors(source: String, pattern: String): List<String> =
		Regex(pattern).findAll(source).map { it.groupValues[1] }.toList()
}
