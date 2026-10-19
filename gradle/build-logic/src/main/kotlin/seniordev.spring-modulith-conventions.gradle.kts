import org.gradle.api.tasks.SourceSetContainer
import org.gradle.api.tasks.testing.Test
import pl.seniordeveloper.gradle.PlatformVersions

/*
 * seniordev.spring-modulith-conventions
 * -------------------------------------
 * Wspólny "kręgosłup" backendu Spring Modulith dla repo konsumentów (scripts/consumers.txt):
 *   - import BOM-ów (Spring Boot / Spring Modulith / Spring AI GA) przez dependency-management
 *   - wspólne zależności TESTOWE (modulith-test, Testcontainers, ArchUnit, junit-launcher)
 *   - TAKSONOMIA TESTÓW (z Attestate): szybki `test` (bez tagu integration) ‖ wolny `integrationTest`
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

// Wersje BOM-ów z gradle/catalog: generatePlatformVersions wpisuje je do PlatformVersions przy kompilacji
// build-logic, więc bump to jeden wpis w libs.versions.toml (dawniej lustro, którego rozjazd był u konsumenta
// cichy: platformDependencyCheck nie widzi importów mavenBom(...)).
val springBootVersion = PlatformVersions.SPRING_BOOT
val springModulithVersion = PlatformVersions.SPRING_MODULITH
val springAiVersion = PlatformVersions.SPRING_AI
val archunitVersion = PlatformVersions.ARCHUNIT
val junitVersion = PlatformVersions.JUNIT

// Boot 4.1.1 manages Netty 4.2.17.Final and PostgreSQL 42.7.13; no override needed for those two.

// Nadpisanie KOMPATYBILNOŚCI (nie CVE) ponad BOM Boot 4.1.1: BOM-owy Lombok 1.18.46 pada na javac 27
// (ClassNotFoundException com.sun.tools.javac.tree.EndPosTable w lombok.javac.Javac), a toolchain
// w java-conventions to 27. 1.18.48 kompiluje na javac 27 (zweryfikowane w Azimuth).
// USUŃ, gdy BOM Boota przypnie lombok.version >= 1.18.48 (propercja w spring-boot-dependencies).
// Wersja z gradle/catalog: lombok (PlatformVersions.LOMBOK).
ext["lombok.version"] = PlatformVersions.LOMBOK

// Nadpisania CVE ponad BOM Boot 4.1.1 (nowszego Boota jeszcze nie ma). Wykrył je canon-cve-scan.yml:
// tomcat-embed-core 11.0.24 — 3x Critical (GHSA-9xv2-5v5q-p794, GHSA-gcx9-497g-6cp6, GHSA-h3x4-894j-xpx5,
// poprawka 11.0.25); jackson 3.1.5 i 2.21.5 — High (np. GHSA-cxp5-3px4-pw24, poprawki 3.1.7 i 2.21.7).
// Najnowsze łatki w tych samych liniach, które zarządza Boot. USUŃ każde, gdy BOM Boota dojdzie do poprawki.
// Wersje z gradle/catalog: tomcat, jacksonBom, jackson2Bom (PlatformVersions).
ext["tomcat.version"] = PlatformVersions.TOMCAT
ext["jackson-bom.version"] = PlatformVersions.JACKSON_BOM
ext["jackson-2-bom.version"] = PlatformVersions.JACKSON_2_BOM

// Właściwości wersji BOM-ów ustawiane przez Platform (wyżej). Konsument, który ustawi dowolną właściwość `*.version`
// (extra/ext albo gradle.properties), omija kanon: dependency-management podstawia ją do zaimportowanych BOM-ów,
// a platformDependencyCheck widzi tylko zadeklarowane zależności. Decyzja 18: ostrzeżenie z listą, nie błąd.
// resolutionStrategy.eachDependency/force są statycznie niewidoczne — zgłasza je platform-bump (docs/versions.md).
val platformBomProperties =
	listOf("lombok.version", "tomcat.version", "jackson-bom.version", "jackson-2-bom.version")
		.associateWith { ext[it].toString() }
val platformBomOverrideCheck =
	tasks.register("platformBomOverrideCheck") {
		description = "Warns about BOM version properties set outside the platform."
		group = "verification"
		val overrides =
			provider {
				project.properties
					.filterKeys { it.endsWith(".version") }
					.mapValues { it.value.toString() }
					.filter { (key, value) -> platformBomProperties[key] != value }
					.toSortedMap()
			}
		inputs.property("overrides", overrides)
		doLast {
			val found = overrides.get()
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
		mavenBom("org.springframework.boot:spring-boot-dependencies:$springBootVersion")
		mavenBom("org.springframework.modulith:spring-modulith-bom:$springModulithVersion")
		mavenBom("org.springframework.ai:spring-ai-bom:$springAiVersion")
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

// Domyślny `test` = szybkie testy jednostkowe (pomija tag "integration").
tasks.named<Test>("test") {
	useJUnitPlatform { excludeTags("integration") }
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
