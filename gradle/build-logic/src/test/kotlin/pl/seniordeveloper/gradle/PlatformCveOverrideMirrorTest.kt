package pl.seniordeveloper.gradle

import java.io.File
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

/**
 * Nadpisania CVE ponad BOM Boota w spring-modulith-conventions mają lustro w katalogu (tomcat, jacksonBom,
 * jackson2Bom). Rozjazd jest cichy: canon-cve-scan.yml i dokumentacja patrzą na katalog, a konsument dostaje
 * wersję z pluginu.
 */
class PlatformCveOverrideMirrorTest {

	private val springModulithConventions =
		File(System.getProperty("platform.springModulithConventions")).readText()

	@Test
	fun `every CVE override in spring-modulith-conventions matches the catalog`() {
		val overrides = mapOf("tomcat.version" to "tomcat", "jackson-bom.version" to "jacksonBom", "jackson-2-bom.version" to "jackson2Bom")
		overrides.forEach { (property, catalogKey) ->
			val pattern = Regex("""ext\["${Regex.escape(property)}"]\s*=\s*"([^"]+)"""")
			assertEquals(
				listOf(System.getProperty("platform.canon.$catalogKey")),
				pattern.findAll(springModulithConventions).map { it.groupValues[1] }.toList(),
				"ext[\"$property\"] in spring-modulith-conventions must equal catalog entry $catalogKey, exactly once",
			)
		}
	}
}
