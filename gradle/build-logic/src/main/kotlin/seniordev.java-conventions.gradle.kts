import org.gradle.api.artifacts.ExternalModuleDependency
import org.gradle.api.artifacts.VersionCatalogsExtension
import org.gradle.api.plugins.quality.Checkstyle
import org.gradle.testing.jacoco.tasks.JacocoCoverageVerification
import org.gradle.testing.jacoco.tasks.JacocoReport
import java.io.File

/*
 * seniordev.java-conventions
 * --------------------------
 * Bazowy "agent-friendly" plugin dla każdego modułu Java w organizacji:
 *   - toolchain Java 26 (non-LTS; baseline portfolio 2026-07)
 *   - Spotless (Google Java Format) — jeden formatter dla wszystkich repo
 *   - Checkstyle (maxWarnings = 0) — twarda konwencja
 *   - JaCoCo + bramka pokrycia z RATCHETEM (start 0.00 → cel 0.80, sterowany -PcoverageMinimum);
 *     pokrycie sumowane z `test` I `integrationTest`, raport i bramka wiszą na `check`
 *
 * Źródło 1:1: najlepsze części z BookOfStyling (googleJavaFormat + checkstyle) ujednolicone
 * dla Attestate (brak narzędzi) i SkillSprintPlus (sam importOrder).
 */

plugins {
	java
	jacoco
	checkstyle
	id("com.diffplug.spotless")
}

// UWAGA: convention plugin NIE deklaruje repositories — repozytoria pochodzą z settings konsumenta
// (dependencyResolutionManagement: mavenLocal + mavenCentral + GitHub Packages). Deklaracja repo
// na poziomie projektu przesłoniłaby je i zepsuła resolucję artefaktów Platform z mavenLocal/GitHub.

java {
	toolchain {
		languageVersion = JavaLanguageVersion.of(26)
	}
}

spotless {
	java {
		googleJavaFormat()
		removeUnusedImports()
		trimTrailingWhitespace()
		endWithNewline()
	}
}

// Współdzielona konfiguracja Checkstyle żyje w resources tego pluginu (jedno źródło w Platform).
// Wypakowujemy ją do build/ i wskazujemy configDirectory, by ${config_loc} trafiał na suppressions.
// Dzięki temu repo konsumenckie NIE trzymają własnych kopii config/checkstyle/.
val checkstyleDir = layout.buildDirectory.dir("platform-config/checkstyle").get().asFile
val checkstyleFiles = listOf("checkstyle.xml", "checkstyle-suppressions.xml").associateWith { name ->
	(object {}.javaClass.classLoader.getResourceAsStream("platform-checkstyle/$name")
		?: error("Brak zasobu platform-checkstyle/$name w pluginie seniordev.java-conventions")).bufferedReader()
		.use { it.readText() }
}
val extractCheckstyleConfig = tasks.register("extractCheckstyleConfig") {
	description = "Wypakowuje współdzieloną konfigurację Checkstyle z pluginu do build/."
	outputs.dir(checkstyleDir)
	doLast {
		checkstyleDir.mkdirs()
		checkstyleFiles.forEach { (name, text) -> File(checkstyleDir, name).writeText(text) }
	}
}

checkstyle {
	toolVersion = "13.10.0"
	maxWarnings = 0
	configDirectory.set(layout.buildDirectory.dir("platform-config/checkstyle"))
	config = resources.text.fromFile(File(checkstyleDir, "checkstyle.xml"))
}

tasks.withType<Checkstyle>().configureEach {
	dependsOn(extractCheckstyleConfig)
}

jacoco {
	// 0.8.15 = najnowsza stabilna; 0.8.14+ = class-file Java 25, 0.8.15 dodał EKSPERYMENTALNE wsparcie 26 (gate pokrycia działa, status nieoficjalny).
	// Lustro gradle/catalog: version("jacoco").
	toolVersion = "0.8.15"
}

tasks.withType<Test>().configureEach {
	useJUnitPlatform()
}

// Pokrycie liczy się z OBU zestawów. `jacocoTestReport` domyślnie czyta wyłącznie `test.exec`, więc
// w repo z osobnym taskiem integracyjnym (spring-modulith-conventions) cały wysiłek Testcontainers
// był wykonywany i wyrzucany: adapter przetestowany ITką raportował 0% pokrycia, a SonarCloud
// pokazywał liczbę zaniżoną o kilka punktów. Wiązanie po NAZWIE, bo `integrationTest` rejestruje
// późniejszy plugin; `modelTest` (pobiera wagi modelu, poza `check`) świadomie zostaje poza sumą,
// żeby wynik lokalny i wynik CI były tą samą liczbą.
val coverageProducers = tasks.matching { it.name == "test" || it.name == "integrationTest" }
val coverageExecutionData =
	fileTree(layout.buildDirectory).include("jacoco/test.exec", "jacoco/integrationTest.exec")

tasks.named<JacocoReport>("jacocoTestReport") {
	dependsOn(coverageProducers)
	executionData.setFrom(coverageExecutionData)
	reports {
		xml.required.set(true)
		html.required.set(true)
	}
}

tasks.named<JacocoCoverageVerification>("jacocoTestCoverageVerification") {
	dependsOn(coverageProducers)
	executionData.setFrom(coverageExecutionData)
	violationRules {
		rule {
			limit {
				// RATCHET: każde repo startuje tam, gdzie ma kod, i podnosi w stronę 0.80.
				// Nadpisz w gradle.properties konsumenta: coverageMinimum=0.80
				minimum = (project.findProperty("coverageMinimum") as String? ?: "0.00").toBigDecimal()
			}
		}
	}
}

// ŚWIADOMIE bez `test { finalizedBy(jacocoTestReport) }`: raport zależy teraz też od
// `integrationTest`, więc finalizer na `test` ciągnąłby Testcontainers przy każdym `./gradlew test`.
// Raport i bramka wiszą na `check` — a tam oba zestawy i tak się wykonują.
tasks.named("check") {
	dependsOn(tasks.named("jacocoTestCoverageVerification"), tasks.named("jacocoTestReport"))
}

// === Governance wersji: KAŻDA wersja biblioteki pochodzi z platform-catalog ====================
// Reguły:
//   1. Zależność zadeklarowana BEZ wersji = zarządzana BOM-ami platformy (spring-modulith-conventions) — OK.
//   2. Zależność z JAWNĄ wersją musi mieć wpis w katalogu `libs` (platform-catalog) z wersją IDENTYCZNĄ
//      — w praktyce: deklaruj wyłącznie przez `libs.<alias>`. Inline wersja spoza katalogu = czerwony build.
//   3. Nowa biblioteka w projekcie = najpierw wpis w Platform (gradle/catalog) + ./release.sh,
//      potem bump pinu i użycie przez libs.<alias>.
// Wykrywanie w afterEvaluate (deps konsumenta już zadeklarowane), asercja w tasku — CC-safe.
val governedConfigurations = setOf(
	"api", "implementation", "compileOnly", "runtimeOnly", "annotationProcessor",
	"testImplementation", "testCompileOnly", "testRuntimeOnly", "testAnnotationProcessor",
)
val platformDependencyCheck = tasks.register("platformDependencyCheck") {
	description = "Pilnuje, że wersje wszystkich zadeklarowanych zależności pochodzą z platform-catalog."
	group = "verification"
}
afterEvaluate {
	val libs = extensions.findByType<VersionCatalogsExtension>()?.find("libs")?.orElse(null)
	val violations = mutableListOf<String>()
	if (libs != null) {
		val canon = mutableMapOf<String, String>()
		libs.libraryAliases.forEach { alias ->
			val dep = libs.findLibrary(alias).get().get()
			val v = dep.versionConstraint.requiredVersion
			if (v.isNotBlank()) canon["${dep.module.group}:${dep.module.name}"] = v
		}
		configurations.matching { it.name in governedConfigurations }.forEach { conf ->
			conf.dependencies.withType(ExternalModuleDependency::class.java).forEach { d ->
				val ver = d.version
				if (ver.isNullOrBlank() || d.group == "pl.seniordeveloper") return@forEach
				val key = "${d.group}:${d.name}"
				val canonV = canon[key]
				if (canonV == null) {
					violations += "$key:$ver (${conf.name}) — BRAK w platform-catalog: dodaj wpis w Platform i wydaj (./release.sh)"
				} else if (canonV != ver) {
					violations += "$key:$ver (${conf.name}) — kanon platformy: $canonV (deklaruj przez libs.<alias>)"
				}
			}
		}
	}
	val catalogMissing = libs == null
	platformDependencyCheck.configure {
		doLast {
			if (catalogMissing) {
				logger.lifecycle("platformDependencyCheck: pominięty — brak katalogu 'libs' (build spoza konsumenta platformy)")
			} else if (violations.isNotEmpty()) {
				throw GradleException(
					"Wersje zależności spoza platformy (governance):\n  " + violations.joinToString("\n  "),
				)
			} else {
				logger.lifecycle("platformDependencyCheck: OK — wszystkie jawne wersje zgodne z platform-catalog")
			}
		}
	}
}
tasks.named("check") {
	dependsOn(platformDependencyCheck)
}
