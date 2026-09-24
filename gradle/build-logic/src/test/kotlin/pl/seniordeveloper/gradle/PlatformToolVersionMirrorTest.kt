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
	fun `pitestVersion w quality-conventions jest zgodny z kanonem katalogu`() {
		val mirrored = mirrors(qualityConventions, """pitestVersion\.set\("([^"]+)"\)""")

		assertEquals(listOf(canon("pitestTool")), mirrored, "pitestVersion.set(...) w quality-conventions musi równać się kanonowi")
	}

	private fun canon(name: String): String = System.getProperty("platform.canon.$name")

	private fun mirrors(source: String, pattern: String): List<String> =
		Regex(pattern).findAll(source).map { it.groupValues[1] }.toList()
}
