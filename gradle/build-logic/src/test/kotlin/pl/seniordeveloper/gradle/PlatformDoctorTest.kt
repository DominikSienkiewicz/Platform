package pl.seniordeveloper.gradle

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import pl.seniordeveloper.gradle.DoctorFinding.Status

class PlatformDoctorTest {
	@Test
	fun `matching pins pass and name every pin`() {
		val finding = DoctorChecks.pins("1.6.0", "1.6.0", "1.6.0")
		assertEquals(Status.PASS, finding.status)
		assertEquals("PASS PD080 seniordev.settings-conventions, platform-catalog, platformVersion are all 1.6.0", finding.render())
	}

	@Test
	fun `a build without platformVersion compares the plugin with the catalog`() {
		assertEquals(Status.PASS, DoctorChecks.pins("1.6.0", "1.6.0", null).status)
		assertEquals(Status.FAIL, DoctorChecks.pins("1.6.0", "1.5.31", null).status)
	}

	@Test
	fun `diverging pins fail with every pin and the fix`() {
		val finding = DoctorChecks.pins("1.6.0", "1.5.31", "1.6.0")
		assertEquals(
			"FAIL PD080 the Gradle-side Platform pins disagree: seniordev.settings-conventions 1.6.0, platform-catalog 1.5.31, " +
				"platformVersion 1.6.0\n          fix: run scripts/platform-bump.sh <version>, or read both pins from platformVersion " +
				"in settings.gradle.kts as docs/consuming.md shows",
			finding.render(),
		)
	}

	@Test
	fun `a build without the catalog fails`() {
		val finding = DoctorChecks.pins("1.6.0", null, "1.6.0")
		assertEquals(Status.FAIL, finding.status)
		assertEquals("the build loads no version catalog libs from platform-catalog", finding.message)
	}

	@Test
	fun `a resolvable toolchain passes with its path and a missing one fails with the fix`() {
		assertEquals(
			"PASS PD081 the Java 27 toolchain resolves to /jdks/27",
			DoctorChecks.toolchain(27) { "/jdks/$it" }.render(),
		)
		val missing = DoctorChecks.toolchain(27) { throw IllegalStateException("No matching toolchains found\nmore detail") }
		assertEquals(Status.FAIL, missing.status)
		assertEquals("no Java 27 toolchain: No matching toolchains found", missing.message)
		assertEquals(Status.PASS, DoctorChecks.toolchain(null) { error("not called") }.status)
	}

	@Test
	fun `coverageMinimum warns when unset, passes as a fraction and fails otherwise`() {
		assertEquals(Status.WARN, DoctorChecks.coverageMinimum(null).status)
		assertEquals("PASS PD082 coverageMinimum is 0.80", DoctorChecks.coverageMinimum(" 0.80 ").render())
		listOf("80", "0,8", "-0.1", "abc").forEach { raw ->
			assertEquals(Status.FAIL, DoctorChecks.coverageMinimum(raw).status, raw)
		}
	}
}
