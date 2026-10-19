package pl.seniordeveloper.gradle

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.nio.file.Path

/** N-REL-6: stary pin dostaje jedną linię na build, świeży — żadnej. */
class PlatformStalenessFunctionalTest {
	@TempDir
	lateinit var directory: Path

	@Test
	fun `the notice appears once for an old release and never for a fresh one`() {
		val release = requireNotNull(PlatformStaleness.load()) { "build-logic must embed its release date" }
		val consumer = ConsumerFixture(directory, "java-library")

		val old = consumer.runner("help", properties = mapOf("platform.staleness.today" to release.releasedAt.plusDays(61).toString())).build()
		assertEquals(1, notices(old.output), "an old release gets exactly one line")

		val fresh = consumer.runner("help", properties = mapOf("platform.staleness.today" to release.releasedAt.toString())).build()
		assertEquals(0, notices(fresh.output), "a fresh release stays silent")

		val silenced =
			consumer
				.runner(
					"help",
					properties = mapOf("platform.staleness.today" to release.releasedAt.plusDays(61).toString(), "platform.staleness.notice" to "false"),
				).build()
		assertEquals(0, notices(silenced.output), "platform.staleness.notice=false silences the notice")
	}

	private fun notices(output: String): Int = output.lineSequence().count { it.startsWith("Platform ") && it.contains(" days ago (") }
}
