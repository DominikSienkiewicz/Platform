import pl.seniordeveloper.gradle.AgentTestBudget
import pl.seniordeveloper.gradle.RuntimeImageCheck
import org.gradle.api.artifacts.ExternalModuleDependency
import org.gradle.api.artifacts.VersionCatalogsExtension
import org.gradle.api.plugins.quality.Checkstyle
import org.gradle.api.tasks.SourceSetContainer
import org.gradle.testing.jacoco.tasks.JacocoCoverageVerification
import org.gradle.testing.jacoco.tasks.JacocoReport
import java.io.File
import java.math.BigDecimal

/*
 * seniordev.java-conventions
 * --------------------------
 * Bazowy "agent-friendly" plugin dla każdego modułu Java w organizacji:
 *   - toolchain Java 27 (non-LTS; baseline portfolio 2026-09). Wymaga Lomboka >= 1.18.48 (nadpisanie
 *     BOM-a w spring-modulith-conventions) i google-java-format >= 1.35.0 (pin niżej)
 *   - Spotless (Google Java Format) — jeden formatter dla wszystkich repo
 *   - Checkstyle (maxWarnings = 0) — twarda konwencja
 *   - JaCoCo + statyczny próg pokrycia `coverageMinimum` (ułamek 0..1, domyślnie 0.00; repo samo go podnosi);
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

// Lustro gradle/catalog: version("java"). Bytecode 27 wymaga runtime'u >= 27 (obraz Dockera konsumenta).
java {
	toolchain {
		languageVersion = JavaLanguageVersion.of(27)
	}
}

// Obraz runtime konsumenta żyje w ręcznie kopiowanym Dockerfile, a toolchain tutaj — nic ich nie wiązało
// (BookOfStyling i SkillSprintPlus: eclipse-temurin:25-jre przy toolchainie 26). Bramka porównuje ostatni
// FROM z toolchainem; brak Dockerfile albo obraz spoza JVM = pominięcie z logiem.
val runtimeDockerfiles =
	listOf(layout.projectDirectory, rootProject.layout.projectDirectory).map { it.file("Dockerfile").asFile }.distinct()
val platformRuntimeImageCheck = tasks.register<RuntimeImageCheck>("platformRuntimeImageCheck") {
	description = "Fails when the Dockerfile's final JVM image runs an older Java than the toolchain of the bytecode."
	group = "verification"
	dockerfiles.set(runtimeDockerfiles)
	toolchainVersion.set(java.toolchain.languageVersion.map { it.asInt() })
}
tasks.named("check") {
	dependsOn(platformRuntimeImageCheck)
}

spotless {
	java {
		// Wersja JAWNIE: domyślna Spotless zależy od JVM demona Gradle i na JDK 27 wybierała 1.28.0,
		// która pada na javac 27 (NoSuchFieldError JCCompilationUnit.endPositions); 1.34.x z kolei
		// odrzuca `var`. Lustro gradle/catalog: version("googleJavaFormat").
		googleJavaFormat("1.36.1")
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
	// Lustro gradle/catalog: version("checkstyle").
	toolVersion = "13.10.0"
	maxWarnings = 0
	configDirectory.set(layout.buildDirectory.dir("platform-config/checkstyle"))
	config = resources.text.fromFile(File(checkstyleDir, "checkstyle.xml"))
}

tasks.withType<Checkstyle>().configureEach {
	dependsOn(extractCheckstyleConfig)
}

jacoco {
	// 0.8.15 = najnowsza stabilna; 0.8.14+ = class-file Java 25, 0.8.15 dodał EKSPERYMENTALNE wsparcie 26; class-file 27 również nieoficjalne (zweryfikowane w Azimuth).
	// Lustro gradle/catalog: version("jacoco").
	toolVersion = "0.8.15"
}

val agentMode = providers.environmentVariable("AI_AGENT").map { it == "1" || it == "true" }.getOrElse(false)
if (agentMode) {
	val testBudget = gradle.sharedServices.registerIfAbsent("platformAgentTestBudget", AgentTestBudget::class) {
		maxParallelUsages.set(1)
	}
	tasks.withType<Test>().configureEach {
		maxParallelForks = 1
		maxHeapSize = "2g"
		systemProperty("spring.test.context.cache.maxSize", "4")
		usesService(testBudget)
	}
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

// Próg pokrycia: STATYCZNY ułamek `coverageMinimum` z gradle.properties konsumenta albo -P, domyślnie 0.00.
// To nie jest ratchet — każde repo startuje tam, gdzie ma kod, i samo podnosi próg w stronę 0.80.
// Walidacja od razu w konfiguracji: "80" dawało próg 80, a "0,8" NumberFormatException bez wskazówki.
val coverageMinimumProperty = providers.gradleProperty("coverageMinimum")
val coverageMinimum: BigDecimal = coverageMinimumProperty.orNull?.let { raw ->
	raw.trim().toBigDecimalOrNull()?.takeIf { it >= BigDecimal.ZERO && it <= BigDecimal.ONE }
		?: throw GradleException("coverageMinimum must be a decimal between 0 and 1 (e.g. 0.80); got '$raw'")
} ?: BigDecimal("0.00")
val coverageGate =
	"Coverage gate: minimum=${coverageMinimum.toPlainString()} " +
		"(source: ${if (coverageMinimumProperty.isPresent) "coverageMinimum" else "default"})"

tasks.named<JacocoCoverageVerification>("jacocoTestCoverageVerification") {
	dependsOn(coverageProducers)
	executionData.setFrom(coverageExecutionData)
	val gate = coverageGate
	doFirst { logger.lifecycle(gate) }
	violationRules {
		rule {
			limit {
				minimum = coverageMinimum
			}
		}
	}
}

// Bramka bez danych to fałszywa zieleń: JacocoCoverageVerification ma onlyIf("Any of the execution data
// files exists"), więc moduł bez .exec przy coverageMinimum > 0 dostawał SKIPPED i zielony `check`.
val mainClassesDirs = the<SourceSetContainer>()["main"].output.classesDirs
val platformCoverageDataCheck = tasks.register("platformCoverageDataCheck") {
	description = "Fails when coverageMinimum is above 0 but no test task produced JaCoCo execution data."
	group = "verification"
	dependsOn(coverageProducers)
	val gateActive = coverageMinimum.signum() > 0
	val minimum = coverageMinimum.toPlainString()
	val executionData = coverageExecutionData
	val mainClasses = mainClassesDirs
	inputs.files(mainClasses)
	doLast {
		val hasMainClasses = mainClasses.asFileTree.any { it.name.endsWith(".class") }
		if (gateActive && hasMainClasses && executionData.isEmpty) {
			throw GradleException(
				"coverageMinimum=$minimum needs JaCoCo execution data, but neither test nor integrationTest produced any. " +
					"Add tests to this module or set coverageMinimum=0.",
			)
		}
	}
}

// ŚWIADOMIE bez `test { finalizedBy(jacocoTestReport) }`: raport zależy teraz też od
// `integrationTest`, więc finalizer na `test` ciągnąłby Testcontainers przy każdym `./gradlew test`.
// Raport i bramka wiszą na `check` — a tam oba zestawy i tak się wykonują.
tasks.named("check") {
	dependsOn(tasks.named("jacocoTestCoverageVerification"), tasks.named("jacocoTestReport"), platformCoverageDataCheck)
}

// === Governance wersji: KAŻDA jawna wersja biblioteki pochodzi z platform-catalog ==============
// Reguły:
//   1. Zależność zadeklarowana BEZ wersji = zarządzana BOM-ami platformy (spring-modulith-conventions) — OK.
//   2. Zależność albo constraint z JAWNĄ wersją musi mieć wpis w katalogu `libs` (platform-catalog) z wersją
//      IDENTYCZNĄ — w praktyce: deklaruj wyłącznie przez `libs.<alias>`. Dotyczy też artefaktów
//      pl.seniordeveloper: ich kanonem jest wstrzyknięta platformVersion. Inline wersja spoza kanonu = czerwony build.
//   3. Nowa biblioteka w projekcie = najpierw wpis w Platform (gradle/catalog) i wydanie,
//      potem bump pinu i użycie przez libs.<alias>.
// Zakres: każdy deklarowalny kubełek — nazwy bazowe niżej i ich warianty z prefiksem source setu (test*,
// testFixtures*, własne source sety). Konfiguracje narzędzi (checkstyle, pitest, spotbugs*, jacocoAgent,
// cyclonedx*) zostają poza zakresem z konstrukcji.
// Wykrywanie w afterEvaluate (deps konsumenta już zadeklarowane), asercja w tasku — CC-safe.
val governedBuckets = setOf(
	"api", "implementation", "compileOnly", "compileOnlyApi", "runtimeOnly", "annotationProcessor",
	"developmentOnly", "testAndDevelopmentOnly",
)
val governedBucketSuffixes =
	listOf("Implementation", "Api", "CompileOnly", "CompileOnlyApi", "RuntimeOnly", "AnnotationProcessor")
fun isGovernedBucket(name: String): Boolean =
	name in governedBuckets || governedBucketSuffixes.any { name.length > it.length && name.endsWith(it) }

val platformDependencyCheck = tasks.register("platformDependencyCheck") {
	description = "Checks that every explicit dependency version comes from platform-catalog."
	group = "verification"
}
afterEvaluate {
	val libs = extensions.findByType<VersionCatalogsExtension>()?.find("libs")?.orElse(null)
	val violations = mutableListOf<String>()
	if (libs != null) {
		val canonVersions = mutableMapOf<String, String>()
		val accessors = mutableMapOf<String, String>()
		libs.libraryAliases.forEach { alias ->
			val dep = libs.findLibrary(alias).get().get()
			val key = "${dep.module.group}:${dep.module.name}"
			accessors.putIfAbsent(key, "libs." + alias.replace('-', '.').replace('_', '.'))
			val v = dep.versionConstraint.requiredVersion
			if (v.isNotBlank()) canonVersions[key] = v
		}
		fun violation(key: String, version: String?, bucket: String): String? {
			if (version.isNullOrBlank()) return null
			val canonVersion = canonVersions[key]
			val accessor = accessors[key]
			return when {
				canonVersion == version -> null
				canonVersion != null -> "$key:$version ($bucket) — Platform canon is $canonVersion: declare it as $accessor"
				accessor != null ->
					"$key:$version ($bucket) — managed by the Platform BOMs: remove the explicit version and declare it as $accessor"
				else ->
					"$key:$version ($bucket) — not in the Platform catalog. If the Platform BOMs (Spring Boot / Modulith / " +
						"Spring AI) manage it, remove the explicit version; otherwise add it to gradle/catalog/libs.versions.toml " +
						"in DominikSienkiewicz/Platform, release, and bump the Platform pin"
			}
		}
		configurations.matching { isGovernedBucket(it.name) }.forEach { conf ->
			conf.dependencies.withType(ExternalModuleDependency::class.java).forEach { d ->
				violation("${d.group}:${d.name}", d.version, conf.name)?.let { violations += it }
			}
			conf.dependencyConstraints.forEach { c ->
				violation("${c.group}:${c.name}", c.version, "${conf.name} constraint")?.let { violations += it }
			}
		}
	}
	val catalogMissing = libs == null
	platformDependencyCheck.configure {
		doLast {
			if (catalogMissing) {
				logger.warn("platformDependencyCheck: skipped — no 'libs' version catalog, so this is not a Platform consumer build")
			} else if (violations.isNotEmpty()) {
				throw GradleException(
					"Dependency versions outside the Platform canon (platformDependencyCheck):\n  " + violations.joinToString("\n  "),
				)
			} else {
				logger.lifecycle("platformDependencyCheck: OK — every explicit version matches platform-catalog")
			}
		}
	}
}
tasks.named("check") {
	dependsOn(platformDependencyCheck)
}
