import org.gradle.api.tasks.SourceSetContainer
import org.gradle.api.tasks.testing.Test

/*
 * seniordev.spring-modulith-conventions
 * -------------------------------------
 * Wspólny "kręgosłup" backendu Spring Modulith dla 3 repo:
 *   - import BOM-ów (Spring Boot / Spring Modulith / Spring AI GA) przez dependency-management
 *   - wspólne zależności TESTOWE (modulith-test, Testcontainers, ArchUnit, junit-launcher)
 *   - TAKSONOMIA TESTÓW (z Attestate): szybki `test` (bez tagu integration) ‖ wolny `integrationTest`
 *
 * Świadomie NIE dodaje zależności biznesowych (security, jOOQ, resilience4j, modele AI) — te są
 * per-repo i deklaruje je konsument przez współdzielony version catalog (`libs`).
 * Konsument NADAL aplikuje plugin Spring Boot: alias(libs.plugins.spring.boot).
 *
 * Wersje BOM/ArchUnit = lustro gradle/catalog (świadoma duplikacja — patrz README).
 */

plugins {
	java
	id("io.spring.dependency-management")
}

// Repozytoria pochodzą z settings konsumenta — patrz seniordev.java-conventions.

// LUSTRA gradle/catalog — precompiled script plugin nie czyta katalogu w czasie kompilacji,
// więc każdy bump w libs.versions.toml musi ruszyć te stałe RAZEM z nim. Rozjazd nie psuje
// buildu Platform (te wersje trafiają dopiero na classpath konsumenta), tylko wywala guard
// governance w backendzie konsumenta: „wersja spoza platformy … kanon platformy: X".
val springBootVersion = "4.1.1"
val springModulithVersion = "2.1.1"
val springAiVersion = "2.0.1"
val archunitVersion = "1.5.0"
val junitVersion = "6.1.3"

// Boot 4.1.1 manages Netty 4.2.17.Final and PostgreSQL 42.7.13; no CVE overrides needed.

// Nadpisanie KOMPATYBILNOŚCI (nie CVE) ponad BOM Boot 4.1.1: BOM-owy Lombok 1.18.46 pada na javac 27
// (ClassNotFoundException com.sun.tools.javac.tree.EndPosTable w lombok.javac.Javac), a toolchain
// w java-conventions to 27. 1.18.48 kompiluje na javac 27 (zweryfikowane w Azimuth).
// USUŃ, gdy BOM Boota przypnie lombok.version >= 1.18.48 (propercja w spring-boot-dependencies).
// Lustro gradle/catalog: version("lombok"); pilnuje PlatformToolVersionMirrorTest.
ext["lombok.version"] = "1.18.48"

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
	// Lustro gradle/catalog: version("archunit"); pilnuje PlatformToolVersionMirrorTest.
	dependencies {
		dependency("com.tngtech.archunit:archunit:$archunitVersion")
	}
}

dependencies {
	// Spring Boot 4.0.x ciągnie junit-bom 5.14.x (launcher 1.14.x), a Modulith/Spring AI/Testcontainers
	// ciągną junit-bom 6.x → mieszany stos (launcher 1.14 vs platform 6.x) wywala każdy engine
	// NoSuchMethodError. enforcedPlatform przypina cały JUnit do jednej wersji (fix realnego buga
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
val integrationTest = tasks.register<Test>("integrationTest") {
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
