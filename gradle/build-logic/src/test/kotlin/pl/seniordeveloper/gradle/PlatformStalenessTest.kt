package pl.seniordeveloper.gradle

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test
import java.time.LocalDate

class PlatformStalenessTest {
	private val release = PlatformRelease("1.5.26", LocalDate.parse("2026-08-10"))

	@Test
	fun `a release inside the window stays silent`() {
		assertNull(PlatformStaleness.notice(release, LocalDate.parse("2026-10-09")))
	}

	@Test
	fun `a release past the window names its age and the fix`() {
		assertEquals(
			"Platform 1.5.26 was released 65 days ago (2026-08-10); the support window is 60 days or 3 releases " +
				"(RELEASING.md, Support policy). Run scripts/platform-bump.sh, or silence this notice with " +
				"-Pplatform.staleness.notice=false.",
			PlatformStaleness.notice(release, LocalDate.parse("2026-10-14")),
		)
	}

	@Test
	fun `a missing or broken date disables the notice`() {
		assertNull(PlatformStaleness.parse("1.5.26", ""))
		assertNull(PlatformStaleness.parse("1.5.26", "yesterday"))
	}

	@Test
	fun `the plugin carries its own version and release date`() {
		val embedded = requireNotNull(PlatformStaleness.load()) { "build-logic must embed platform-release.properties" }
		assertEquals(PlatformVersions.PLATFORM, embedded.version)
	}
}
