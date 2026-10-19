package pl.seniordeveloper.gradle

import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.nio.file.Path

/**
 * gradle/canon-probe/build.gradle.kts buduje tylko canon-cve-scan.yml, więc żaden PR go nie kompilował: po 957043b
 * skrypt odwoływał się do `java.util.Properties`, a `java` w skrypcie z pluginem Java to rozszerzenie `java { }`,
 * nie pakiet, i job backend padał na kompilacji skryptu. Test kompiluje i konfiguruje prawdziwy skrypt probe'a
 * na konwencjach z repozytorium testowego. Settings są własne, bo includeBuild z settings probe'a kompilowałby
 * build-logic ze źródeł drugi raz.
 */
class CanonProbeFunctionalTest {
	@TempDir
	lateinit var directory: Path

	@Test
	fun `the probe declares the platform-bom of the scanned canon`() {
		val gradleModules = File(System.getProperty("platform.gradleModules"))
		val canon = directory.resolve("canon").toFile()
		gradleModules.resolve("catalog/libs.versions.toml").copyTo(canon.resolve("gradle/catalog/libs.versions.toml"))
		canon.resolve("gradle/bom/gradle.properties").apply { parentFile.mkdirs() }.writeText("platformVersion=$SCANNED_VERSION\n")
		val probe = directory.resolve("probe")
		gradleModules.resolve("canon-probe/build.gradle.kts").copyTo(probe.resolve("build.gradle.kts").toFile())
		probe.resolve("settings.gradle.kts").toFile().writeText(SETTINGS)

		val output =
			ConsumerFixture
				.existing(probe)
				.runner("dependencies", "--configuration", "implementation", properties = mapOf("canonRoot" to canon.absolutePath))
				.build()
				.output

		assertTrue(output.contains("pl.seniordeveloper:platform-bom:$SCANNED_VERSION"), output)
	}

	private companion object {
		const val SCANNED_VERSION = "0.0.1-scanned"

		val SETTINGS =
			"""
			pluginManagement {
				repositories {
					maven { url = uri(providers.gradleProperty("platformRepository").get()) }
					gradlePluginPortal()
					mavenCentral()
				}
				resolutionStrategy {
					eachPlugin {
						if (requested.id.namespace == "seniordev") useVersion(providers.gradleProperty("platformVersion").get())
					}
				}
			}

			dependencyResolutionManagement {
				repositories { mavenCentral() }
				versionCatalogs {
					create("libs") {
						from(files(providers.gradleProperty("canonRoot").get() + "/gradle/catalog/libs.versions.toml"))
					}
				}
			}

			rootProject.name = "canon-probe"
			""".trimIndent()
	}
}
