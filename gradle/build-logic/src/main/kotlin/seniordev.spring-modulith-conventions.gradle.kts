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

val springBootVersion = "4.0.6"
val springModulithVersion = "2.0.6"
val springAiVersion = "2.0.0-M8" // GA jeszcze nie wyszło; M8 = najnowszy milestone (jest na Maven Central)
val archunitVersion = "1.4.2"
val junitVersion = "6.1.0"

// TYMCZASOWE nadpisania CVE ponad BOM Boot 4.0.6 (najnowszy GA na 2026-06; 4.1.0 dopiero RC1).
// Mechanizm: io.spring.dependency-management honoruje nadpisanie propercji wersji z BOM-a przez ext.
// USUŃ przy bumpie springBoot, gdy BOM dogoni te wersje (sprawdź propercje w spring-boot-dependencies):
//   tomcat 11.0.22      — GHSA-r29c-68gh-xp6x, GHSA-h6fc-48rj-7qqh, GHSA-5m62-pw8w-7w9f (Critical) i in.
//   netty 4.2.13.Final  — GHSA-f6hv-jmp6-3vwv, GHSA-rwm7-x88c-3g2p i in.
//   postgresql 42.7.11  — GHSA-98qh-xjc8-98pq
ext["tomcat.version"] = "11.0.22"
ext["netty.version"] = "4.2.13.Final"
ext["postgresql.version"] = "42.7.11"

dependencyManagement {
	imports {
		mavenBom("org.springframework.boot:spring-boot-dependencies:$springBootVersion")
		mavenBom("org.springframework.modulith:spring-modulith-bom:$springModulithVersion")
		mavenBom("org.springframework.ai:spring-ai-bom:$springAiVersion")
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
