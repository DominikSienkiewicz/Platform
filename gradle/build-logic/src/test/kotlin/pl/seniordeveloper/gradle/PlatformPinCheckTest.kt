package pl.seniordeveloper.gradle

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

class PlatformPinCheckTest {
	@Test
	fun `the mismatch names both pins and the command that aligns them`() {
		assertEquals(
			"The Platform pins diverge: seniordev.settings-conventions is 1.6.0, platform-catalog is 1.5.31. The conventions " +
				"then apply the BOMs and tools of 1.6.0 to the canon of 1.5.31, so other gates fail for the wrong reason. " +
				"Align both pins with scripts/platform-bump.sh 1.5.31, or read both from platformVersion in " +
				"settings.gradle.kts (docs/consuming.md).",
			PlatformPinCheck.mismatch("1.6.0", "1.5.31"),
		)
	}
}
