package pl.seniordeveloper.gradle

import java.io.File
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir

/**
 * Guard zgodności platform-checkstyle z google-java-format (Spotless).
 *
 * Spotless w seniordev.java-conventions formatuje kod przez googleJavaFormat(), a Checkstyle
 * weryfikuje TEN SAM kod. Każda konstrukcja, którą google-java-format wymusza, MUSI przechodzić
 * przez checkstyle.xml — inaczej konsument wpada w ping-pong: spotlessApply psuje checkstyle
 * i odwrotnie, bez żadnego formatowania spełniającego oba narzędzia.
 */
class PlatformCheckstyleConfigTest {

	@TempDir
	lateinit var tempDir: File

	@Test
	fun `pusta lambda w formacie google-java-format przechodzi checkstyle`() {
		// google-java-format renderuje pustą lambdę jako `() -> {}` (bez spacji w klamrach).
		val fixture = File(tempDir, "EmptyLambdaFixture.java")
		fixture.writeText(
			"""
			package pl.seniordeveloper.gradle.fixture;

			class EmptyLambdaFixture {
			  private final Runnable noop = () -> {};
			}
			""".trimIndent() + "\n",
		)

		val violations = CheckstyleAudit.violations(tempDir, listOf(fixture))

		assertTrue(
			violations.isEmpty(),
			"checkstyle.xml odrzuca kod w formacie google-java-format:\n" + CheckstyleAudit.describe(violations),
		)
	}
}
