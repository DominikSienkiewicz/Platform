package pl.seniordeveloper.gradle

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File

/**
 * Akcja taska (`doLast`), która sięga po zmienną poziomu skryptu precompiled pluginu, kompiluje się do lambdy
 * z polem `this$0` typu klasy skryptu — configuration cache nie umie tego zserializować i każdy konsument
 * z `org.gradle.configuration-cache=true` dostaje czerwony build. Test czyta skompilowane klasy pluginów,
 * jak `javap`: lambdy akcji taska `extract*Config` (zagnieżdżone `…$extractXConfig$1$1`) nie mogą trzymać
 * obiektu skryptu. Pełny dowód z TestKit i `--configuration-cache` daje E1-15.
 */
class PlatformTaskActionCaptureTest {
	private val classesDir =
		File(
			Class
				.forName("Seniordev_java_conventions_gradle")
				.protectionDomain.codeSource.location
				.toURI(),
		)

	@Test
	fun `extract task actions do not capture the plugin script object`() {
		val actions =
			classesDir
				.listFiles()!!
				.map { it.name.removeSuffix(".class") }
				.filter { Regex("""^Seniordev_\w+_gradle\${'$'}extract\w+Config\${'$'}\d+\${'$'}\d+$""").matches(it) }
		assertEquals(2, actions.size, "expected the doLast actions of extractCheckstyleConfig and extractSpotbugsConfig, found $actions")
		actions.forEach { name ->
			val captured = Class.forName(name).declaredFields.filter { it.type.name.matches(Regex("""^Seniordev_\w+_gradle$""")) }
			assertTrue(captured.isEmpty(), "$name captures the script object through ${captured.map { it.name }}")
		}
	}
}
