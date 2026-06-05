import org.gradle.api.plugins.quality.Checkstyle
import org.gradle.testing.jacoco.tasks.JacocoCoverageVerification
import org.gradle.testing.jacoco.tasks.JacocoReport
import java.io.File

/*
 * seniordev.java-conventions
 * --------------------------
 * Bazowy "agent-friendly" plugin dla każdego modułu Java w organizacji:
 *   - toolchain Java 25 (LTS)
 *   - Spotless (Google Java Format) — jeden formatter dla wszystkich repo
 *   - Checkstyle (maxWarnings = 0) — twarda konwencja
 *   - JaCoCo + bramka pokrycia z RATCHETEM (start 0.00 → cel 0.80, sterowany -PcoverageMinimum)
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
		languageVersion = JavaLanguageVersion.of(25)
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
	toolVersion = "13.5.0"
	maxWarnings = 0
	configDirectory.set(layout.buildDirectory.dir("platform-config/checkstyle"))
	config = resources.text.fromFile(File(checkstyleDir, "checkstyle.xml"))
}

tasks.withType<Checkstyle>().configureEach {
	dependsOn(extractCheckstyleConfig)
}

jacoco {
	// 0.8.14 dodaje wsparcie class-file dla Javy 25 (LTS).
	toolVersion = "0.8.14"
}

tasks.withType<Test>().configureEach {
	useJUnitPlatform()
}

tasks.named<JacocoReport>("jacocoTestReport") {
	dependsOn(tasks.named("test"))
	reports {
		xml.required.set(true)
		html.required.set(true)
	}
}

tasks.named("test") {
	finalizedBy(tasks.named("jacocoTestReport"))
}

tasks.named<JacocoCoverageVerification>("jacocoTestCoverageVerification") {
	dependsOn(tasks.named("test"))
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

tasks.named("check") {
	dependsOn(tasks.named("jacocoTestCoverageVerification"))
}
