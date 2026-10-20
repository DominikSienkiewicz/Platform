import org.gradle.api.tasks.SourceSetContainer
import org.gradle.api.tasks.testing.Test
import pl.seniordeveloper.gradle.PlatformVersions

/*
 * seniordev.spring-modulith-conventions
 * -------------------------------------
 * Wspólny "kręgosłup" backendu Spring Modulith dla repo konsumentów (scripts/consumers.txt):
 *   - import pl.seniordeveloper:platform-bom (BOM-y Boot / Modulith / Spring AI / JUnit + podłogi CVE) przez dependency-management
 *   - wspólne zależności TESTOWE (modulith-test, Testcontainers, ArchUnit, junit-launcher)
 *   - TAKSONOMIA TESTÓW (z Attestate): szybki `test` ‖ wolny `integrationTest` ‖ świadomy `modelTest` (poza check)
 *
 * Świadomie NIE dodaje zależności biznesowych (security, jOOQ, resilience4j, modele AI) — te są
 * per-repo i deklaruje je konsument przez współdzielony version catalog (`libs`).
 * Konsument NADAL aplikuje plugin Spring Boot: alias(libs.plugins.spring.boot).
 *
 * Wersje BOM/ArchUnit/JUnit = gradle/catalog przez wygenerowany PlatformVersions (precompiled script plugin nie
 * czyta katalogu w czasie kompilacji — patrz docs/versions.md i zasada 1 w CLAUDE.md).
 */

plugins {
	java
	id("io.spring.dependency-management")
}

// Repozytoria pochodzą z settings konsumenta — patrz seniordev.java-conventions.

// BOM-y i ograniczenia z jednego miejsca (N-CAP-12, ADR-0013): pl.seniordeveloper:platform-bom tego samego
// wydania importuje BOM-y Boota, Modulith, Spring AI i JUnit oraz poprawione BOM-y Jacksona (przed Bootem, bo
// w imporcie Maven wygrywa pierwszy), a jego constraints niosą podłogę Tomcata i nadpisania Lomboka i ArchUnit
// z uzasadnieniem. Dawniej stały tu trzy importy i cztery `ext[...]`, osobno od BOM-u, który konsumenci spoza
// Springa importowali sami. Wersja BOM-u = PlatformVersions.PLATFORM, czyli wydanie tych konwencji.
val platformVersion = PlatformVersions.PLATFORM
val archunitVersion = PlatformVersions.ARCHUNIT
val junitVersion = PlatformVersions.JUNIT

// Platform nie ustawia już żadnej właściwości wersji BOM-u (podłogi niesie platform-bom). Konsument, który ustawi
// dowolną właściwość `*.version` (extra/ext albo gradle.properties), omija kanon: dependency-management podstawia ją
// do zaimportowanych BOM-ów, a platformDependencyCheck widzi tylko zadeklarowane zależności. Decyzja 18: ostrzeżenie
// z listą, nie błąd. Podłóg z platform-bom (np. Jackson) taka właściwość nie obniży: ich import stoi przed Bootem.
// resolutionStrategy.eachDependency/force są statycznie niewidoczne — zgłasza je platform-bump (docs/versions.md).
val platformBomProperties = emptyMap<String, String>()
val platformBomOverrideCheck =
	tasks.register("platformBomOverrideCheck") {
		description = "Warns about BOM version properties set outside the platform."
		group = "verification"
		// Właściwości z gradle.properties/-P i ext/extra skryptu, bez przestarzałego Project.getProperties (Gradle 10).
		val gradleProperties = providers.gradlePropertiesPrefixedBy("")
		val extraProperties = project.extensions.extraProperties
		val overrides =
			provider {
				(gradleProperties.get() + extraProperties.properties.mapValues { it.value.toString() })
					.filterKeys { it.endsWith(".version") }
					.filter { (key, value) -> platformBomProperties[key] != value }
					.toSortedMap()
			}
		inputs.property("overrides", overrides)
		// Raport zamiast ciągłego ponownego wykonania (N-REL-15): ostrzeżenia wracają, gdy zmienią się właściwości.
		val report = layout.buildDirectory.file("reports/platform/bom-override-check.txt")
		outputs.file(report)
		doLast {
			val found = overrides.get()
			report
				.get()
				.asFile
				.apply { parentFile.mkdirs() }
				.writeText(found.entries.joinToString("") { "${it.key}=${it.value}\n" })
			found.forEach { (key, value) ->
				logger.warn(
					"platformBomOverrideCheck: $key=$value overrides the Platform BOMs outside the platform. Move the override " +
						"to Platform (seniordev.spring-modulith-conventions) and release, or remove it once the Platform BOMs manage that version.",
				)
			}
			if (found.isEmpty()) logger.lifecycle("platformBomOverrideCheck: OK — no BOM version property is set outside the platform")
		}
	}
tasks.named("check") {
	dependsOn(platformBomOverrideCheck)
}

dependencyManagement {
	imports {
		mavenBom("pl.seniordeveloper:platform-bom:$platformVersion")
	}
	// Nadpisanie KOMPATYBILNOŚCI (nie CVE) dla RUNTIME: spring-modulith-core 2.1.1 deklaruje ArchUnit 1.4.2
	// jako zależność compile, a żaden BOM (Boot/Modulith) nie zarządza ArchUnit — nie ma propercji do
	// nadpisania przez ext. ArchUnit 1.4.2 nie czyta class-file 71 (javac 27, toolchain java-conventions),
	// więc ApplicationModules budowane przy starcie aplikacji nie importuje żadnej klasy i kontekst pada
	// z „No classes found in packages". Testy tego nie łapią: archunit-junit5 niżej wciąga wersję z kanonu
	// tylko na testowe classpathy. Zarządzana zależność działa na WSZYSTKICH konfiguracjach, w tym tranzytywnie.
	// USUŃ, gdy spring-modulith-core przypnie ArchUnit >= 1.5.0 (sprawdź pom spring-modulith-core).
	// Wersja z gradle/catalog: archunit (PlatformVersions.ARCHUNIT).
	dependencies {
		dependency("com.tngtech.archunit:archunit:$archunitVersion")
	}
}

dependencies {
	// BOM-y Boota, Modulith, Spring AI i Testcontainers nie muszą zgadzać się co do linii JUnit (przy Boocie 4.0
	// Boot dawał junit-bom 5.14 / launcher 1.14, reszta 6.x) → mieszany stos launcher vs platform wywala
	// każdy engine NoSuchMethodError. enforcedPlatform przypina cały JUnit do jednej wersji (fix realnego buga
	// ze SkillSprintPlus — teraz egzekwowany centralnie, nie per-repo).
	"testImplementation"(enforcedPlatform("org.junit:junit-bom:$junitVersion"))
	"testImplementation"("org.springframework.modulith:spring-modulith-starter-test")
	"testImplementation"("org.springframework.boot:spring-boot-testcontainers")
	"testImplementation"("org.testcontainers:testcontainers-junit-jupiter")
	"testImplementation"("com.tngtech.archunit:archunit-junit5:$archunitVersion")
	"testRuntimeOnly"("org.junit.platform:junit-platform-launcher")
}

val testSourceSet = the<SourceSetContainer>()["test"]

tasks.withType<Test>().configureEach {
	useJUnitPlatform()
}

// Domyślny `test` = szybkie testy jednostkowe (pomija tagi "integration" i "model").
tasks.named<Test>("test") {
	useJUnitPlatform { excludeTags("integration", "model") }
}

// Testy integracyjne (Testcontainers) — wolniejsze, osobny task, po `test`.
val integrationTest =
	tasks.register<Test>("integrationTest") {
		description = "Uruchamia testy oznaczone tagiem \"integration\" (Testcontainers)."
		group = "verification"
		testClassesDirs = testSourceSet.output.classesDirs
		classpath = testSourceSet.runtimeClasspath
		useJUnitPlatform { includeTags("integration") }
		shouldRunAfter(tasks.named("test"))
	}

// `check` (a więc i `build`) odpala oba zestawy.
tasks.named("check") {
	dependsOn(integrationTest)
}

// Testy modelu (@ModelTest, N-CAP-8): wolne przebiegi, np. z modelem w PlatformOllamaContainer (pobiera wagi),
// uruchamiane świadomie, poza `check` i poza sumą pokrycia, więc nie wydłużają każdego PR-a.
// Rejestracja po skrypcie projektu, jak `lint` i `format` w java-conventions: projekt z własnym `modelTest`
// (Azimuth: większy heap pod model ONNX) zostaje przy swoim, zamiast paść na "Cannot add task 'modelTest'".
afterEvaluate {
	if ("modelTest" in tasks.names) {
		logger.warn(
			"seniordev.spring-modulith-conventions: $path defines its own modelTest task, so the Platform modelTest is not registered there",
		)
	} else {
		tasks.register<Test>("modelTest") {
			description = "Runs the tests tagged model; outside check, run it on purpose."
			group = "verification"
			testClassesDirs = testSourceSet.output.classesDirs
			classpath = testSourceSet.runtimeClasspath
			useJUnitPlatform { includeTags("model") }
			shouldRunAfter(tasks.named("test"))
		}
	}
}
