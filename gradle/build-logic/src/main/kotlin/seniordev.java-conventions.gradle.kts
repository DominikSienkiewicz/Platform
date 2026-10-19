import io.spring.gradle.dependencymanagement.dsl.DependencyManagementExtension
import org.gradle.api.artifacts.ExternalModuleDependency
import org.gradle.api.artifacts.VersionCatalogsExtension
import org.gradle.api.plugins.quality.Checkstyle
import org.gradle.api.tasks.SourceSet
import org.gradle.api.tasks.SourceSetContainer
import org.gradle.testing.jacoco.tasks.JacocoCoverageVerification
import org.gradle.testing.jacoco.tasks.JacocoReport
import pl.seniordeveloper.gradle.AgentTestBudget
import pl.seniordeveloper.gradle.DeclaredDependency
import pl.seniordeveloper.gradle.DependencyGovernance
import pl.seniordeveloper.gradle.PlatformDependencyCheck
import pl.seniordeveloper.gradle.PlatformDeprecations
import pl.seniordeveloper.gradle.PlatformExtension
import pl.seniordeveloper.gradle.PlatformGates
import pl.seniordeveloper.gradle.PlatformPinCheck
import pl.seniordeveloper.gradle.PlatformQuarantineCheck
import pl.seniordeveloper.gradle.PlatformVersions
import pl.seniordeveloper.gradle.RuntimeImageCheck
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
 *   - `platformPinCheck` (settings plugin i katalog z jednego wydania) oraz taski `lint` i `format`
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
// (dependencyResolutionManagement: opcjonalne -PplatformRepository, mavenCentral, GitHub Packages). Deklaracja
// repo na poziomie projektu przesłoniłaby je i zepsuła resolucję artefaktów Platform.

// Wersja z gradle/catalog: java (PlatformVersions.JAVA). Bytecode 27 wymaga runtime'u >= 27 (obraz Dockera konsumenta).
// -PplatformToolchainOverride=<N> (N-REL-4) tylko dla kanarka i eksperymentów z następnym JDK: kanonem zostaje katalog.
val toolchainOverride = providers.gradleProperty("platformToolchainOverride").map { it.trim().toInt() }.orNull
if (toolchainOverride != null) {
	logger.warn(
		"seniordev.java-conventions: platformToolchainOverride=$toolchainOverride replaces the Java ${PlatformVersions.JAVA} toolchain of the Platform canon; use it for canaries only",
	)
}
java {
	toolchain {
		languageVersion = JavaLanguageVersion.of(toolchainOverride ?: PlatformVersions.JAVA)
	}
}

// Ostrzeżenia javac (N-CAP-11): -Xlint:all poza processing (szum procesorów adnotacji) i serial (Serializable bez
// serialVersionUID w encjach i DTO). -Pplatform.javac.werror=true zamienia ostrzeżenia w błędy, gdy repo jest gotowe —
// zapadka, nie domyślna; z seniordev.nullness-conventions obejmuje też ostrzeżenia Error Prone.
val javacWerror = providers.gradleProperty("platform.javac.werror").map { it.trim() == "true" }.getOrElse(false)
tasks.withType<JavaCompile>().configureEach {
	options.compilerArgs.addAll(listOf("-Xlint:all", "-Xlint:-processing", "-Xlint:-serial"))
	if (javacWerror) options.compilerArgs.add("-Werror")
}

// Obraz runtime konsumenta żyje w ręcznie kopiowanym Dockerfile, a toolchain tutaj — nic ich nie wiązało
// (BookOfStyling i SkillSprintPlus: eclipse-temurin:25-jre przy toolchainie 26). Bramka porównuje ostatni
// FROM z toolchainem; brak Dockerfile albo obraz spoza JVM = pominięcie z logiem.
val runtimeDockerfiles =
	listOf(layout.projectDirectory, rootProject.layout.projectDirectory).map { it.file("Dockerfile").asFile }.distinct()
val platformRuntimeImageCheck =
	tasks.register<RuntimeImageCheck>("platformRuntimeImageCheck") {
		description = "Fails when the Dockerfile's final JVM image runs an older Java than the toolchain of the bytecode."
		group = "verification"
		dockerfiles.set(runtimeDockerfiles)
		toolchainVersion.set(java.toolchain.languageVersion.map { it.asInt() })
		result.set(layout.buildDirectory.file("platform/runtime-image-check.txt"))
	}
tasks.named("check") {
	dependsOn(platformRuntimeImageCheck)
}

spotless {
	java {
		// Wersja JAWNIE: domyślna Spotless zależy od JVM demona Gradle i na JDK 27 wybierała 1.28.0,
		// która pada na javac 27 (NoSuchFieldError JCCompilationUnit.endPositions); 1.34.x z kolei
		// odrzuca `var`. Wersja z gradle/catalog: googleJavaFormat.
		googleJavaFormat(PlatformVersions.GOOGLE_JAVA_FORMAT)
		removeUnusedImports()
		trimTrailingWhitespace()
		endWithNewline()
	}
}

// Współdzielona konfiguracja Checkstyle żyje w resources tego pluginu (jedno źródło w Platform).
// Wypakowujemy ją do build/ i wskazujemy configDirectory, by ${config_loc} trafiał na suppressions.
// Dzięki temu repo konsumenckie NIE trzymają własnych kopii config/checkstyle/.
val checkstyleDir =
	layout.buildDirectory
		.dir("platform-config/checkstyle")
		.get()
		.asFile
val checkstyleFiles =
	listOf("checkstyle.xml", "checkstyle-suppressions.xml").associateWith { name ->
		(
			object {}.javaClass.classLoader.getResourceAsStream("platform-checkstyle/$name")
				?: error("Brak zasobu platform-checkstyle/$name w pluginie seniordev.java-conventions")
		).bufferedReader()
			.use { it.readText() }
	}
// Lokalne kopie w bloku register: akcja doLast trzyma wtedy tylko je, a nie obiekt skryptu pluginu, którego
// configuration cache nie serializuje. Pilnuje PlatformTaskActionCaptureTest.
val extractCheckstyleConfig =
	tasks.register("extractCheckstyleConfig") {
		description = "Wypakowuje współdzieloną konfigurację Checkstyle z pluginu do build/."
		val outputDir = layout.buildDirectory.dir("platform-config/checkstyle")
		val files = checkstyleFiles
		inputs.property("files", files)
		outputs.dir(outputDir)
		doLast {
			val dir = outputDir.get().asFile
			dir.mkdirs()
			files.forEach { (name, text) -> File(dir, name).writeText(text) }
		}
	}

checkstyle {
	// Wersja z gradle/catalog: checkstyle.
	toolVersion = PlatformVersions.CHECKSTYLE
	maxWarnings = 0
	configDirectory.set(layout.buildDirectory.dir("platform-config/checkstyle"))
	config = resources.text.fromFile(File(checkstyleDir, "checkstyle.xml"))
}

tasks.withType<Checkstyle>().configureEach {
	dependsOn(extractCheckstyleConfig)
	// Najpierw formatowanie: naruszenie, które naprawia `format`, ma wyjść przed Checkstyle'em, którego część reguł
	// zgłasza ten sam problem — kolejność niezależnych tasków w `lint` zależała dotąd od czasu kompilacji.
	mustRunAfter("spotlessCheck")
}

jacoco {
	// 0.8.15 = najnowsza stabilna; 0.8.14+ = class-file Java 25, 0.8.15 dodał EKSPERYMENTALNE wsparcie 26; class-file 27 również nieoficjalne (zweryfikowane w Azimuth).
	// Wersja z gradle/catalog: jacoco.
	toolVersion = PlatformVersions.JACOCO
}

// Profil agenta (ADR-0010, N-SHOW-2): AI_AGENT=1/true zmienia DOMYŚLNE wartości, a jawnie ustawiona właściwość działa
// w każdym trybie. springContextCacheSize to nazwa, której Azimuth już używa, więc jego konfiguracja działa bez zmian.
val agentMode = providers.environmentVariable("AI_AGENT").map { it == "1" || it == "true" }.getOrElse(false)
val agentTestForks =
	providers
		.gradleProperty("platformAgentTestForks")
		.orNull
		?.trim()
		?.toInt() ?: if (agentMode) 1 else null
val agentTestHeap = providers.gradleProperty("platformAgentTestHeap").orNull?.trim() ?: if (agentMode) "2g" else null
val agentContextCache = providers.gradleProperty("springContextCacheSize").orNull?.trim() ?: if (agentMode) "4" else null
if (agentMode && !gradle.extra.has("platformAgentProfileAnnounced")) {
	// Jedna linia na build, nie na projekt: transkrypt agenta pokazuje, jaki budżet obowiązywał.
	gradle.extra["platformAgentProfileAnnounced"] = true
	logger.lifecycle(
		"Platform agent profile: testForks=$agentTestForks testHeap=$agentTestHeap springContextCache=$agentContextCache (AI_AGENT=1)",
	)
}
val testBudget =
	if (agentMode) {
		gradle.sharedServices.registerIfAbsent("platformAgentTestBudget", AgentTestBudget::class) {
			maxParallelUsages.set(1)
		}
	} else {
		null
	}
tasks.withType<Test>().configureEach {
	agentTestForks?.let { maxParallelForks = it }
	agentTestHeap?.let { maxHeapSize = it }
	agentContextCache?.let { systemProperty("spring.test.context.cache.maxSize", it) }
	testBudget?.let { usesService(it) }
}

// === Taksonomia testów (N-CAP-8) i kwarantanna (N-REL-13) ===================================================
// Baseline JUnit z kanonu: BOM, Jupiter i launcher bez trzech linii w każdym repo; -Pplatform.junitBaseline=false wyłącza.
if (providers.gradleProperty("platform.junitBaseline").orNull?.trim() != "false") {
	dependencies {
		"testImplementation"(platform("org.junit:junit-bom:${PlatformVersions.JUNIT}"))
		"testImplementation"("org.junit.jupiter:junit-jupiter")
		"testRuntimeOnly"("org.junit.platform:junit-platform-launcher")
	}
}
// Każdy Test task podaje nazwę strażnikowi kontenerów z test-fixtures (PlatformTestTaskGuard), a testy w kwarantannie
// biegną tylko w quarantineTest, poza `check`.
val quarantineTag = "quarantine"
tasks.withType<Test>().configureEach {
	systemProperty("platform.test.task", name)
	if (name != "quarantineTest") {
		useJUnitPlatform { excludeTags(quarantineTag) }
	}
}
val quarantineTestSourceSet = the<SourceSetContainer>()["test"]
val quarantineScannedSources = the<SourceSetContainer>().matching { it.name != SourceSet.MAIN_SOURCE_SET_NAME }
tasks.register<Test>("quarantineTest") {
	description = "Runs the tests tagged quarantine; they keep reporting, but never fail the build."
	group = "verification"
	testClassesDirs = quarantineTestSourceSet.output.classesDirs
	classpath = quarantineTestSourceSet.runtimeClasspath
	useJUnitPlatform { includeTags(quarantineTag) }
	ignoreFailures = true
}
val platformQuarantineCheck =
	tasks.register<PlatformQuarantineCheck>("platformQuarantineCheck") {
		description = "Fails on a quarantined test without an issue and a date, and on an expired one on CI."
		group = "verification"
		sources.from(provider { quarantineScannedSources.flatMap { it.allSource.srcDirs } })
		ci.set(providers.environmentVariable("CI").map { it == "true" }.orElse(false))
		today.set(providers.gradleProperty("platform.quarantineToday"))
		report.set(layout.buildDirectory.file("reports/platform/quarantine.txt"))
	}
tasks.named("check") {
	dependsOn(platformQuarantineCheck)
}
// -Pplatform.testRetry=detect albo PLATFORM_TEST_RETRY=detect (backend-ci): jedno powtórzenie, a build zostaje czerwony,
// gdy test przeszedł dopiero za drugim razem — raport rozróżnia niestabilne od zepsutych, nic nie jest ukryte.
// Właściwość wygrywa ze zmienną, więc -Pplatform.testRetry=off w gradle-task wyłącza wykrywanie w backend-ci.
val testRetryMode =
	providers
		.gradleProperty("platform.testRetry")
		.orElse(providers.environmentVariable("PLATFORM_TEST_RETRY"))
		.orNull
		?.trim()
if (testRetryMode == "detect") {
	pluginManager.apply("org.gradle.test-retry")
	tasks.withType<Test>().configureEach {
		extensions.configure<org.gradle.testretry.TestRetryTaskExtension>("retry") {
			maxRetries.set(1)
			failOnPassedAfterRetry.set(true)
		}
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
// named { } (Gradle 8.6+) filtruje po nazwie bez realizowania wszystkich zarejestrowanych tasków, jak robił matching.
val coverageProducers = tasks.named { it == "test" || it == "integrationTest" }
val coverageExecutionData =
	fileTree(layout.buildDirectory) { include("jacoco/test.exec", "jacoco/integrationTest.exec") }

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
// N-DX-15: `platform { coverage { minimum } }` wygrywa z właściwością; obie są czytane leniwie, przy konfiguracji taska,
// a finalizeValueOnRead zamienia późne ustawienie (po odczycie) w błąd zamiast cichego zignorowania.
val platformSettings = PlatformExtension.of(project)
platformSettings.coverage.minimum.finalizeValueOnRead()
val coverageMinimumProperty = providers.gradleProperty("coverageMinimum")

fun invalidCoverageMinimum(
	source: String,
	raw: String,
): Nothing =
	throw GradleException(
		PlatformGates.line(PlatformGates.COVERAGE_INVALID, "$source must be a decimal between 0 and 1 (e.g. 0.80); got '$raw'") +
			"\n" + PlatformGates.footer(listOf(PlatformGates.COVERAGE_INVALID)),
	)

val coverageMinimumSource: Provider<String> =
	platformSettings.coverage.minimum
		.map { "platform.coverage.minimum" }
		.orElse(coverageMinimumProperty.map { "coverageMinimum" })
		.orElse("default")
// Właściwość waliduje się od razu, jak dotąd (błędna wartość failuje każdy build, także `help`); pole bloku `platform`
// dopiero przy odczycie, bo skrypt konsumenta ustawia je po zaaplikowaniu konwencji.
val coverageMinimumFromProperty: BigDecimal? =
	coverageMinimumProperty.orNull?.let { raw ->
		raw.trim().toBigDecimalOrNull()?.takeIf { it >= BigDecimal.ZERO && it <= BigDecimal.ONE }
			?: invalidCoverageMinimum("coverageMinimum", raw)
	}
val coverageMinimum: Provider<BigDecimal> =
	platformSettings.coverage.minimum
		.map { value ->
			value.takeIf { it >= BigDecimal.ZERO && it <= BigDecimal.ONE }
				?: invalidCoverageMinimum("platform.coverage.minimum", value.toPlainString())
		}.orElse(providers.provider { coverageMinimumFromProperty })
		.orElse(BigDecimal("0.00"))

tasks.named<JacocoCoverageVerification>("jacocoTestCoverageVerification") {
	dependsOn(coverageProducers)
	executionData.setFrom(coverageExecutionData)
	val minimum = coverageMinimum.get()
	val gate = "Coverage gate: minimum=${minimum.toPlainString()} (source: ${coverageMinimumSource.get()})"
	doFirst { logger.lifecycle(gate) }
	violationRules {
		rule {
			limit {
				this.minimum = minimum
			}
		}
	}
}

// Bramka bez danych to fałszywa zieleń: JacocoCoverageVerification ma onlyIf("Any of the execution data
// files exists"), więc moduł bez .exec przy coverageMinimum > 0 dostawał SKIPPED i zielony `check`.
val mainClassesDirs = the<SourceSetContainer>()["main"].output.classesDirs
val platformCoverageDataCheck =
	tasks.register("platformCoverageDataCheck") {
		description = "Fails when coverageMinimum is above 0 but no test task produced JaCoCo execution data."
		group = "verification"
		dependsOn(coverageProducers)
		val gateActive = coverageMinimum.get().signum() > 0
		val minimum = coverageMinimum.get().toPlainString()
		val executionData = coverageExecutionData
		val mainClasses = mainClassesDirs
		val footer = PlatformGates.footer(listOf(PlatformGates.COVERAGE_NO_DATA))
		val stamp = layout.buildDirectory.file("platform/coverage-data-check.txt")
		inputs.files(mainClasses).withPropertyName("mainClasses").withPathSensitivity(PathSensitivity.RELATIVE)
		inputs.files(executionData).withPropertyName("executionData").withPathSensitivity(PathSensitivity.RELATIVE)
		inputs.property("coverageMinimum", minimum)
		// Znacznik wyniku: bez wyjścia task wykonywałby się w każdym buildzie, także bez zmian (N-REL-15).
		outputs.file(stamp)
		doLast {
			stamp.get().asFile.delete()
			val hasMainClasses = mainClasses.asFileTree.any { it.name.endsWith(".class") }
			if (gateActive && hasMainClasses && executionData.isEmpty()) {
				throw GradleException(
					PlatformGates.line(
						PlatformGates.COVERAGE_NO_DATA,
						"coverageMinimum=$minimum needs JaCoCo execution data, but neither test nor integrationTest produced any. " +
							"Add tests to this module or set coverageMinimum=0.",
					) + "\n" + footer,
				)
			}
			stamp
				.get()
				.asFile
				.apply { parentFile.mkdirs() }
				.writeText("coverageMinimum=$minimum\n")
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
val governedBuckets =
	setOf(
		"api",
		"implementation",
		"compileOnly",
		"compileOnlyApi",
		"runtimeOnly",
		"annotationProcessor",
		"developmentOnly",
		"testAndDevelopmentOnly",
	)
val governedBucketSuffixes =
	listOf("Implementation", "Api", "CompileOnly", "CompileOnlyApi", "RuntimeOnly", "AnnotationProcessor")

fun isGovernedBucket(name: String): Boolean =
	name in governedBuckets || governedBucketSuffixes.any { name.length > it.length && name.endsWith(it) }

// Kanon osadzony w pluginie (E1-6), nie katalog `libs` konsumenta: `version(...)` po `from(...)` w settings
// nie przestawi już kanonu po cichu. Zależności zbiera provider wyliczany po konfiguracji projektu (F-14), więc
// widzi też te, które dopisał późniejszy afterEvaluate skryptu albo innego pluginu.
val platformCanon =
	(
		object {}.javaClass.classLoader.getResourceAsStream("platform-canon.tsv")
			?: error("Brak zasobu platform-canon.tsv w pluginie seniordev.java-conventions")
	).bufferedReader()
		.use { DependencyGovernance.parseCanon(it.readText()) }
val platformDeprecationEntries = PlatformDeprecations.load()
val declaredDependencies =
	provider {
		configurations
			.filter { isGovernedBucket(it.name) }
			.flatMap { conf ->
				conf.dependencies.withType(ExternalModuleDependency::class.java).mapNotNull { d ->
					d.version?.takeIf { it.isNotBlank() }?.let { DeclaredDependency("${d.group}:${d.name}", it, conf.name) }
				} +
					conf.dependencyConstraints.mapNotNull { c ->
						c.version?.takeIf { it.isNotBlank() }?.let { DeclaredDependency("${c.group}:${c.name}", it, "${conf.name} constraint") }
					}
			}
	}
val consumerLibs = extensions.findByType<VersionCatalogsExtension>()?.find("libs")?.orElse(null)
val platformDependencyCheck =
	tasks.register<PlatformDependencyCheck>("platformDependencyCheck") {
		description = "Checks that every explicit dependency version comes from the Platform canon embedded in the plugin."
		group = "verification"
		val canonEntries = platformCanon
		projectPath.set(project.path)
		declared.set(declaredDependencies.map { list -> list.map { it.encode() } })
		canon.set(canonEntries.mapValues { (_, entry) -> "${entry.version}\t${entry.accessor}" })
		catalogPresent.set(consumerLibs != null)
		consumerCatalog.set(
			provider {
				consumerLibs?.libraryAliases?.associate { alias ->
					val library = consumerLibs.findLibrary(alias).get().get()
					"${library.module.group}:${library.module.name}" to library.versionConstraint.requiredVersion
				} ?: emptyMap()
			},
		)
		// Pytanie o BOM-y rozwiązuje je, więc pada tylko dla zależności spoza kanonu. Rozszerzenie szukane dopiero
		// tu: spring-modulith-conventions aplikuje dependency-management po tym pluginie.
		val projectExtensions = project.extensions
		bomManaged.set(
			declaredDependencies.map { list ->
				val keys = DependencyGovernance.uncataloged(list, canonEntries)
				val management = projectExtensions.findByType<DependencyManagementExtension>()
				if (keys.isEmpty() || management == null) emptyMap() else management.managedVersions.filterKeys { it in keys }
			},
		)
		val entries = platformDeprecationEntries
		declaredModules.set(
			provider {
				configurations
					.filter { isGovernedBucket(it.name) }
					.flatMap { conf -> conf.dependencies.withType(ExternalModuleDependency::class.java).map { "${it.group}:${it.name}" } }
					.toSet()
			},
		)
		deprecations.set(entries.map(PlatformDeprecations::encode))
		propertiesSet.set(
			provider { entries.filter { it.kind == "property" && providers.gradleProperty(it.id).isPresent }.map { it.id }.toSet() },
		)
		pluginsApplied.set(provider { entries.filter { it.kind == "plugin" && pluginManager.hasPlugin(it.id) }.map { it.id }.toSet() })
		failOnDeprecation.set(providers.gradleProperty("platform.deprecations").map { it == "fail" }.orElse(false))
		exempt.set(DependencyGovernance.GRADLE_INJECTED)
		report.set(layout.buildDirectory.file("reports/platform/dependency-check.md"))
	}
tasks.named("check") {
	dependsOn(platformDependencyCheck)
}

// === Piny Platform: settings plugin (= wersja tych convention pluginów) kontra platform-catalog =============
// Rozjazd daje mylące porażki pozostałych bramek, więc przyczyna pada od razu: ostrzeżenie w konfiguracji
// i task platformPinCheck w `check` i `lint` (sama porażka zostaje w tasku, żeby nie blokować `help` ani `tasks`).
val catalogPlatformVersion =
	extensions
		.findByType<VersionCatalogsExtension>()
		?.find("libs")
		?.orElse(null)
		?.findVersion("platform")
		?.orElse(null)
		?.requiredVersion
if (catalogPlatformVersion != null && catalogPlatformVersion != PlatformVersions.PLATFORM) {
	logger.warn(PlatformPinCheck.mismatch(PlatformVersions.PLATFORM, catalogPlatformVersion))
}
val platformPinCheck =
	tasks.register<PlatformPinCheck>("platformPinCheck") {
		description = "Fails when the settings plugin and platform-catalog are pinned to different Platform releases."
		group = "verification"
		pluginVersion.set(PlatformVersions.PLATFORM)
		catalogVersion.set(catalogPlatformVersion)
		result.set(layout.buildDirectory.file("platform/pin-check.txt"))
	}
tasks.named("check") {
	dependsOn(platformPinCheck)
}

// === lint i format: formatter i lintery bez testów — domyślna bramka agentów i szybki pierwszy krok CI =========
// Rejestracja po skrypcie projektu: projekt, który ma własny `lint` albo `format`, zostaje przy swoim.
afterEvaluate {
	if ("lint" in tasks.names) {
		logger.warn("seniordev.java-conventions: $path defines its own lint task, so the Platform lint is not registered there")
	} else {
		tasks.register("lint") {
			description =
				"Runs the formatter check and the linters without tests: spotlessCheck, Checkstyle, platformDependencyCheck, platformPinCheck, platformQuarantineCheck."
			group = "verification"
			dependsOn("spotlessCheck", tasks.withType<Checkstyle>(), platformDependencyCheck, platformPinCheck, platformQuarantineCheck)
		}
	}
	if ("format" in tasks.names) {
		logger.warn("seniordev.java-conventions: $path defines its own format task, so the Platform format is not registered there")
	} else {
		tasks.register("format") {
			description = "Formats the sources with Spotless (google-java-format)."
			group = "formatting"
			dependsOn("spotlessApply")
		}
	}
}
