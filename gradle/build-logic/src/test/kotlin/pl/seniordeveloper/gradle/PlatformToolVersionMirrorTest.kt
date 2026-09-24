package pl.seniordeveloper.gradle

import java.io.File
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

/**
 * Guard lustra wersji google-java-format.
 *
 * Precompiled script plugin nie czyta katalogu w czasie kompilacji, więc wersja formatera stoi
 * w źródle seniordev.java-conventions i w gradle/catalog jednocześnie. Rozjazd nie psuje buildu
 * Platform, a formater konsumenta wybiera wtedy wersję, której kanon nie opisuje.
 */
class PlatformToolVersionMirrorTest {

	@Test
	fun `googleJavaFormat w java-conventions jest zgodny z kanonem katalogu`() {
		val canon = System.getProperty("platform.canon.googleJavaFormat")
		val source = File(System.getProperty("platform.javaConventions")).readText()

		val mirrored = Regex("""googleJavaFormat\("([^"]+)"\)""").findAll(source).map { it.groupValues[1] }.toList()

		assertEquals(listOf(canon), mirrored, "googleJavaFormat(...) w java-conventions musi równać się kanonowi")
	}
}
