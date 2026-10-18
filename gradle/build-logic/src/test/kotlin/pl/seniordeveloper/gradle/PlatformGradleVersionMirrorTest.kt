package pl.seniordeveloper.gradle

import java.io.File
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

/**
 * Wersja Gradle ma jedno źródło w katalogu (gradle), a lustra w wrapperach modułów Platform i w skanie kanonu.
 * Minimum konsumenta ma źródło w gradle.properties build-logic, a lustro w settings-conventions.
 */
class PlatformGradleVersionMirrorTest {

	private val catalogGradle = System.getProperty("platform.canon.gradle")

	@Test
	fun `every Platform wrapper runs the catalog Gradle`() {
		val wrappers = File(System.getProperty("platform.gradleModules")).listFiles()!!
			.map { File(it, "gradle/wrapper/gradle-wrapper.properties") }
			.filter { it.isFile }
		assertEquals(4, wrappers.size, "build-logic, catalog, test-fixtures and security-starter each carry a wrapper")
		wrappers.forEach { wrapper ->
			val version = Regex("""distributionUrl=.*gradle-([0-9.]+)-(?:bin|all)\.zip""").find(wrapper.readText())?.groupValues?.get(1)
			assertEquals(catalogGradle, version, "${wrapper.parentFile.parentFile.parentFile.name}: the wrapper must run catalog entry gradle")
		}
	}

	@Test
	fun `the JVM starters carry the catalog Gradle wrapper`() {
		val wrappers = File(System.getProperty("platform.templates")).listFiles()!!
			.map { File(it, "gradle/wrapper/gradle-wrapper.properties") }
			.filter { it.isFile }
		assertEquals(listOf("java-library"), wrappers.map { it.parentFile.parentFile.parentFile.name }, "backend-ci-smoke runs the java-library starter's wrapper")
		wrappers.forEach { wrapper ->
			val version = Regex("""distributionUrl=.*gradle-([0-9.]+)-(?:bin|all)\.zip""").find(wrapper.readText())?.groupValues?.get(1)
			assertEquals(catalogGradle, version, "templates/jvm/${wrapper.parentFile.parentFile.parentFile.name}: the wrapper must run catalog entry gradle")
		}
	}

	@Test
	fun `the canon scan installs the catalog Gradle`() {
		val workflow = File(System.getProperty("platform.workflows"), "canon-cve-scan.yml").readText()
		assertEquals(
			listOf(catalogGradle),
			Regex("""gradle-version:\s*"([^"]+)"""").findAll(workflow).map { it.groupValues[1] }.toList(),
			"canon-cve-scan.yml must install catalog entry gradle",
		)
	}

	@Test
	fun `the settings plugin enforces the tested minimum`() {
		val settings = File(System.getProperty("platform.settingsConventions")).readText()
		assertEquals(
			listOf(System.getProperty("platform.minimumConsumerGradle")),
			Regex("""GradleVersion\.version\("([^"]+)"\)""").findAll(settings).map { it.groupValues[1] }.toList(),
			"seniordev.settings-conventions must enforce minimumConsumerGradle from gradle/build-logic/gradle.properties",
		)
	}
}
