package pl.seniordeveloper.gradle

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File

/**
 * Każda property Gradle i zmienna środowiskowa czytana przez convention pluginy to pokrętło konsumenta:
 * bez wpisu w docs/reference.md konsument dowiaduje się o nim dopiero z kodu źródłowego pluginu.
 */
class PlatformReferenceDocTest {
	private val sources = File(System.getProperty("platform.conventionSources"))
	private val reference = File(System.getProperty("platform.referenceDoc")).readText()

	@Test
	fun `every property and environment variable the plugins read is documented in docs reference`() {
		val knobs =
			sources
				.walk()
				.filter { it.isFile && (it.name.endsWith(".kts") || it.name.endsWith(".kt")) }
				.flatMap { source -> knobCall.findAll(source.readText()).map { it.groupValues[1] } }
				.toSortedSet()

		assertTrue(knobs.isNotEmpty(), "No gradleProperty, findProperty or environmentVariable call found under $sources")
		assertEquals(
			emptyList<String>(),
			knobs.filterNot { reference.contains("`$it`") },
			"Read by the convention plugins but missing from docs/reference.md; document each one as `name`",
		)
	}

	private companion object {
		val knobCall = Regex("""(?:gradleProperty|findProperty|environmentVariable)\("([^"]+)"\)""")
	}
}
