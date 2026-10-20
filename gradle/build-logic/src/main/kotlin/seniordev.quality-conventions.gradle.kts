/*
 * seniordev.quality-conventions
 * -----------------------------
 * "Deep quality" — narzędzia, które budują sygnał dojrzałości (security/FinTech positioning):
 *   - PIT (mutation testing) — realna jakość testów, nie tylko pokrycie
 *   - SpotBugs — analiza statyczna (report-only do kryteriów wyjścia z docs/adr/0005-spotbugs-report-only.md)
 *   - CycloneDX — SBOM (./gradlew cyclonedxBom) jako artefakt release
 *
 * targetClasses dla PIT: `platform { mutation { targetPackages.add("pl.seniordeveloper.attestate") } }` (N-DX-15),
 * albo jak dotąd pitest { targetClasses.set(listOf("pl.seniordeveloper.attestate.*")) }; bez obu PIT bierze `<group>.*`.
 * Próg siły mutacji: `platform { mutation { threshold } }` albo `platform.mutation.threshold`, ułamek 0..1; bez obu bez progu.
 *
 * SonarQube (F-13): plugin org.sonarqube żyje w KORZENIU hierarchii — tu tylko wtedy, gdy ten projekt jest rootem
 * (konsument jednomodułowy). Wielomodułowy root aplikuje seniordev.sonar-conventions, a moduły dopisują do analizy
 * własny raport JaCoCo przez rozszerzenie `sonar`, które root nadaje wszystkim projektom.
 */

import com.github.spotbugs.snom.SpotBugsTask
import org.cyclonedx.gradle.CyclonedxDirectTask
import org.sonarqube.gradle.SonarExtension
import pl.seniordeveloper.gradle.PlatformExtension
import pl.seniordeveloper.gradle.PlatformGates
import pl.seniordeveloper.gradle.PlatformSonar
import pl.seniordeveloper.gradle.PlatformVersions
import java.io.File
import java.math.BigDecimal
import java.math.RoundingMode

plugins {
	java
	id("info.solidsoft.pitest")
	id("com.github.spotbugs")
	id("org.cyclonedx.bom")
}

val platformSettings = PlatformExtension.of(project)
platformSettings.mutation.threshold.finalizeValueOnRead()

// Próg jako ułamek 0..1, jak coverageMinimum; PIT chce pełnych procentów, więc zaokrąglamy w górę — nigdy łagodniej,
// niż napisał konsument. Właściwość waliduje się od razu, pole bloku `platform` dopiero przy odczycie (PLAT-MUT-001).
fun invalidMutationThreshold(
	source: String,
	raw: String,
): Nothing =
	throw GradleException(
		PlatformGates.line(PlatformGates.MUTATION_INVALID, "$source must be a decimal between 0 and 1 (e.g. 0.60); got '$raw'") +
			"\n" + PlatformGates.footer(listOf(PlatformGates.MUTATION_INVALID)),
	)

fun BigDecimal.isFraction(): Boolean = this >= BigDecimal.ZERO && this <= BigDecimal.ONE

val mutationThresholdFromProperty: BigDecimal? =
	providers.gradleProperty("platform.mutation.threshold").orNull?.let { raw ->
		raw.trim().toBigDecimalOrNull()?.takeIf { it.isFraction() }
			?: invalidMutationThreshold("platform.mutation.threshold", raw)
	}
val mutationThresholdPercent: Provider<Int> =
	platformSettings.mutation.threshold
		.map { value ->
			value.takeIf { it.isFraction() } ?: invalidMutationThreshold("platform { mutation { threshold } }", value.toPlainString())
		}.orElse(providers.provider { mutationThresholdFromProperty })
		.map { it.movePointRight(2).setScale(0, RoundingMode.CEILING).intValueExact() }

// Repozytoria pochodzą z settings konsumenta — patrz seniordev.java-conventions.

pitest {
	// Wersje przypięte jawnie. PIT >= 1.30.0 czyta class-file 71 (toolchain 27); 1.25.3 niosło ASM 9.9.1
	// i padało na „Unsupported class file major version 71". Wersje z gradle/catalog (PlatformVersions): pitestJunit5
	// dla junit5PluginVersion i version("pitestTool") dla pitestVersion.
	junit5PluginVersion.set(PlatformVersions.PITEST_JUNIT5)
	pitestVersion.set(PlatformVersions.PITEST_TOOL)
	timestampedReports.set(false)
	outputFormats.set(listOf("HTML", "XML"))
	// N-DX-15: pusta lista zostawia targetClasses bez wartości, a wtedy plugin PIT bierze swoje `<group>.*`.
	targetClasses.set(
		platformSettings.mutation.targetPackages.map { packages -> packages.map { "$it.*" }.toSet().takeIf { it.isNotEmpty() } },
	)
	mutationThreshold.set(mutationThresholdPercent)
}

// SBOM = powierzchnia PRODUKCYJNA (to, co shippujemy). Domyślnie plugin bierze WSZYSTKIE
// konfiguracje, więc do skanu CVE wpadał tooling (np. plexus-utils z konfiguracji checkstyle)
// i wywalał gate'a Grype na zależnościach, których nie wdrażamy.
tasks.withType<CyclonedxDirectTask>().configureEach {
	includeConfigs.set(listOf("runtimeClasspath"))
}

// Współdzielony filtr wykluczeń SpotBugs żyje w resources tego pluginu (jedno źródło w Platform);
// wypakowujemy do build/. Repo konsumenckie NIE trzymają własnych kopii config/spotbugs/.
val spotbugsExclude =
	(
		object {}.javaClass.classLoader.getResourceAsStream("platform-spotbugs/spotbugs-exclude.xml")
			?: error("Brak zasobu platform-spotbugs/spotbugs-exclude.xml w pluginie seniordev.quality-conventions")
	).bufferedReader()
		.use { it.readText() }
// Lokalne kopie w bloku register, jak w extractCheckstyleConfig (configuration cache; PlatformTaskActionCaptureTest).
val extractSpotbugsConfig =
	tasks.register("extractSpotbugsConfig") {
		description = "Wypakowuje współdzielony spotbugs-exclude.xml z pluginu do build/."
		val outputDir = layout.buildDirectory.dir("platform-config/spotbugs")
		val text = spotbugsExclude
		inputs.property("spotbugsExclude", text)
		outputs.dir(outputDir)
		doLast {
			val dir = outputDir.get().asFile
			dir.mkdirs()
			File(dir, "spotbugs-exclude.xml").writeText(text)
		}
	}

spotbugs {
	// Wersja z gradle/catalog (PlatformVersions.SPOTBUGS).
	toolVersion.set(PlatformVersions.SPOTBUGS)
	// Report-only do spełnienia kryteriów wyjścia z docs/adr/0005-spotbugs-report-only.md. Konsument przełącza przez
	// `platform { staticAnalysis { failOnBugs.set(true) } }` (N-DX-15) albo jak dotąd spotbugs { ignoreFailures.set(false) }.
	ignoreFailures.set(
		platformSettings.staticAnalysis.failOnBugs
			.map { !it }
			.orElse(true),
	)
	excludeFilter.set(layout.buildDirectory.file("platform-config/spotbugs/spotbugs-exclude.xml"))
}

tasks.withType<SpotBugsTask>().configureEach {
	dependsOn(extractSpotbugsConfig)
}

// ===== SonarCloud =====
// Wspólna konfiguracja SonarCloud (sonarcloud.io) — repo nie deklarują inline id("org.sonarqube") ani bloku sonar{}
// (zasada 8). Wersja pluginu z gradle/catalog (zależność build-logic). Ustawienia całej analizy (host, organizacja,
// projectKey) i zależność `sonar` → raporty JaCoCo: PlatformSonar.
if (project.path == ":") {
	pluginManager.apply("org.sonarqube")
	PlatformSonar.configureAnalysis(project, platformSettings)
}

// Raport pokrycia tego modułu idzie do analizy u roota: w jednomodułowym buildzie to ten sam projekt, w wielomodułowym
// rozszerzenie `sonar` istnieje, gdy root zaaplikował seniordev.sonar-conventions. Bez niego moduł nie ma analizy
// (dawniej miał osobny `:<moduł>:sonar` z tym samym projectKey, czyli siedem częściowych analiz — F-13).
val moduleCoverageReport = layout.buildDirectory.file("reports/jacoco/test/jacocoTestReport.xml")
extensions.findByType<SonarExtension>()?.properties {
	property("sonar.coverage.jacoco.xmlReportPaths", moduleCoverageReport.get().asFile.path)
}
