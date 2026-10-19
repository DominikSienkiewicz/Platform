package pl.seniordeveloper.gradle

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File

/**
 * Wersje, które convention pluginy narzucają konsumentom, pochodzą z kanonu przez wygenerowany PlatformVersions
 * (L-2): stałe równają się katalogowi, a źródła convention pluginów nie zawierają już literału wersji, który
 * mógłby się z nim rozjechać.
 */
class PlatformVersionsTest {
	private val conventions =
		listOf("platform.javaConventions", "platform.qualityConventions", "platform.springModulithConventions")
			.associateWith { File(System.getProperty(it)).readText() }

	@Test
	fun `every generated constant equals its catalog entry`() {
		val generated =
			mapOf(
				"java" to PlatformVersions.JAVA.toString(),
				"googleJavaFormat" to PlatformVersions.GOOGLE_JAVA_FORMAT,
				"checkstyle" to PlatformVersions.CHECKSTYLE,
				"jacoco" to PlatformVersions.JACOCO,
				"spotbugs" to PlatformVersions.SPOTBUGS,
				"pitestTool" to PlatformVersions.PITEST_TOOL,
				"pitestJunit5" to PlatformVersions.PITEST_JUNIT5,
				"springBoot" to PlatformVersions.SPRING_BOOT,
				"springModulith" to PlatformVersions.SPRING_MODULITH,
				"springAi" to PlatformVersions.SPRING_AI,
				"junit" to PlatformVersions.JUNIT,
				"archunit" to PlatformVersions.ARCHUNIT,
				"lombok" to PlatformVersions.LOMBOK,
				"tomcat" to PlatformVersions.TOMCAT,
				"jacksonBom" to PlatformVersions.JACKSON_BOM,
				"jackson2Bom" to PlatformVersions.JACKSON_2_BOM,
			)
		generated.forEach { (catalogKey, value) ->
			assertEquals(canon(catalogKey), value, "PlatformVersions for $catalogKey must equal the catalog entry")
		}
	}

	@Test
	fun `the convention sources carry no version literal`() {
		val literal = Regex(""""\d+\.\d+(\.\d+)?(\.Final)?"|JavaLanguageVersion\.of\(\d+\)""")
		val allowed = setOf("\"0.00\"")
		conventions.forEach { (property, source) ->
			val found =
				literal
					.findAll(source)
					.map { it.value }
					.filterNot { it in allowed }
					.toList()
			assertTrue(found.isEmpty(), "${System.getProperty(property)} hard-codes $found; take the version from PlatformVersions")
		}
	}

	private fun canon(name: String): String =
		checkNotNull(System.getProperty("platform.canon.$name")) { "build-logic test task does not pass platform.canon.$name" }
}
