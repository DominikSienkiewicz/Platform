package pl.seniordeveloper.gradle

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class DependencyGovernanceTest {
	private val canon =
		DependencyGovernance.parseCanon(
			"org.jsoup:jsoup\t1.22.1\tlibs.jsoup\norg.springframework.boot:spring-boot-starter-webmvc\t\tlibs.boot.starter.webmvc\n" +
				"pl.seniordeveloper:platform-test-fixtures\t1.6.0\tlibs.platform.test.fixtures\n",
		)

	@Test
	fun `each kind of violation carries its code and an actionable message`() {
		val declared =
			listOf(
				DeclaredDependency("org.jsoup:jsoup", "1.22.1", "implementation"),
				DeclaredDependency("org.jsoup:jsoup", "1.0.0", "implementation"),
				DeclaredDependency("org.springframework.boot:spring-boot-starter-webmvc", "4.0.0", "implementation"),
				DeclaredDependency("org.springframework.boot:spring-boot-starter-mail", "4.0.0", "implementation"),
				DeclaredDependency("com.example:unknown", "1.0", "testImplementation constraint"),
			)
		val findings = DependencyGovernance.violations(declared, canon, mapOf("org.springframework.boot:spring-boot-starter-mail" to "4.1.1"))

		assertEquals(
			listOf(
				"[PLAT-DEP-002] org.jsoup:jsoup:1.0.0 (implementation) — Platform canon is 1.22.1: declare it as libs.jsoup",
				"[PLAT-DEP-003] org.springframework.boot:spring-boot-starter-webmvc:4.0.0 (implementation) — managed by the Platform " +
					"BOMs: remove the explicit version and declare it as libs.boot.starter.webmvc",
				"[PLAT-DEP-003] org.springframework.boot:spring-boot-starter-mail:4.0.0 (implementation) — the Platform BOMs manage it " +
					"at 4.1.1: remove the explicit version. To run another version on purpose, override the BOM property instead, " +
					"which platformBomOverrideCheck reports",
				"[PLAT-DEP-001] com.example:unknown:1.0 (testImplementation constraint) — not in the Platform catalog and no Platform " +
					"BOM manages it: add it to gradle/catalog/libs.versions.toml in DominikSienkiewicz/Platform, release, and bump the Platform pin",
			),
			findings.map { it.render() },
		)
		assertEquals(
			setOf("org.springframework.boot:spring-boot-starter-mail", "com.example:unknown"),
			DependencyGovernance.uncataloged(declared, canon),
		)
	}

	@Test
	fun `the launcher Gradle injects with a version of its choosing is exempt`() {
		val declared =
			listOf(
				DeclaredDependency("org.junit.platform:junit-platform-launcher", "1.14.4", "testRuntimeOnly"),
				DeclaredDependency("com.example:unknown", "1.0", "testRuntimeOnly"),
			)

		val findings = DependencyGovernance.violations(declared, canon, emptyMap(), DependencyGovernance.GRADLE_INJECTED)

		assertEquals(listOf("com.example:unknown:1.0 (testRuntimeOnly)"), findings.map { it.text.substringBefore(" —") })
	}

	@Test
	fun `a consumer catalog that overrides the canon is a violation, except for Platform artifacts`() {
		val findings =
			DependencyGovernance.catalogOverrides(
				mapOf(
					"org.jsoup:jsoup" to "1.0.0",
					"org.springframework.boot:spring-boot-starter-webmvc" to "",
					"pl.seniordeveloper:platform-test-fixtures" to "0.0.0",
				),
				canon,
			)

		assertEquals(
			listOf(
				"[PLAT-DEP-004] the libs catalog sets org.jsoup:jsoup to 1.0.0, but the Platform canon is 1.22.1: remove the " +
					"version(...) override of libs.jsoup from settings.gradle.kts",
			),
			findings.map { it.render() },
		)
	}

	@Test
	fun `the report links every code to the docs of the release`() {
		val report =
			DependencyGovernance.report(
				":app",
				listOf(GateFinding(PlatformGates.DEP_NOT_IN_CATALOG, "a | b")),
				listOf(GateFinding(PlatformGates.DEPRECATED, "dependency x is deprecated")),
			)

		assertTrue(report.contains("### platformDependencyCheck — :app"))
		assertTrue(report.contains("| [PLAT-DEP-001](${PlatformGates.link("PLAT-DEP-001")}) | a \\| b |"))
		assertTrue(report.contains("- [PLAT-DEPR-001](${PlatformGates.link("PLAT-DEPR-001")}) dependency x is deprecated"))
		assertTrue(PlatformGates.link("PLAT-DEP-001", "1.6.0").endsWith("/blob/v1.6.0/docs/gates.md#plat-dep-001"))
	}
}
