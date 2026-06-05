/*
 * seniordev.quality-conventions
 * -----------------------------
 * "Deep quality" — narzędzia, które budują sygnał dojrzałości (security/FinTech positioning):
 *   - PIT (mutation testing) — realna jakość testów, nie tylko pokrycie
 *   - SpotBugs — analiza statyczna (report-only na JDK 25, bo bytecode-support narzędzi dojrzewa)
 *   - CycloneDX — SBOM (./gradlew cyclonedxBom) jako artefakt release
 *
 * targetClasses dla PIT ustawia KONSUMENT (zależy od groupId modułu), np.:
 *   pitest { targetClasses.set(listOf("pl.seniordeveloper.attestate.*")) }
 */

import com.github.spotbugs.snom.SpotBugsTask
import java.io.File

plugins {
	java
	id("info.solidsoft.pitest")
	id("com.github.spotbugs")
	id("org.cyclonedx.bom")
}

repositories {
	mavenCentral()
}

pitest {
	// Wersje przypięte jawnie pod toolchain Java 25.
	junit5PluginVersion.set("1.2.3")
	pitestVersion.set("1.25.3")
	timestampedReports.set(false)
	outputFormats.set(listOf("HTML", "XML"))
}

// Współdzielony filtr wykluczeń SpotBugs żyje w resources tego pluginu (jedno źródło w Platform);
// wypakowujemy do build/. Repo konsumenckie NIE trzymają własnych kopii config/spotbugs/.
val spotbugsDir = layout.buildDirectory.dir("platform-config/spotbugs").get().asFile
val spotbugsExclude = (object {}.javaClass.classLoader.getResourceAsStream("platform-spotbugs/spotbugs-exclude.xml")
	?: error("Brak zasobu platform-spotbugs/spotbugs-exclude.xml w pluginie seniordev.quality-conventions"))
	.bufferedReader().use { it.readText() }
val extractSpotbugsConfig = tasks.register("extractSpotbugsConfig") {
	description = "Wypakowuje współdzielony spotbugs-exclude.xml z pluginu do build/."
	outputs.dir(spotbugsDir)
	doLast {
		spotbugsDir.mkdirs()
		File(spotbugsDir, "spotbugs-exclude.xml").writeText(spotbugsExclude)
	}
}

spotbugs {
	toolVersion.set("4.9.8")
	// Report-only dopóki wsparcie bytecode JDK 25 w SpotBugs nie jest w pełni zielone.
	// Konsument może przełączyć: spotbugs { ignoreFailures.set(false) }
	ignoreFailures.set(true)
	excludeFilter.set(layout.buildDirectory.file("platform-config/spotbugs/spotbugs-exclude.xml"))
}

tasks.withType<SpotBugsTask>().configureEach {
	dependsOn(extractSpotbugsConfig)
}
