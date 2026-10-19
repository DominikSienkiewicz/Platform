package pl.seniordeveloper.gradle

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class PlatformDeprecationsTest {
	@Test
	fun `the shipped channel parses and names a replacement for every entry`() {
		val entries = PlatformDeprecations.load()

		assertTrue(entries.any { it.id == "org.springframework.boot:spring-boot-starter-web" })
		entries.forEach { assertTrue(it.replacement.isNotBlank() && Regex("""\d+\.\d+\.\d+""").matches(it.since), "$it") }
	}

	@Test
	fun `only what the project uses is reported, each kind by its own signal`() {
		val entries =
			PlatformDeprecations.parse(
				"# comment\ndependency\tg:a\t1.6.0\t1.7.0\tg:b\nproperty\tplatformOld\t1.6.0\t1.7.0\tplatformNew\nplugin\told.plugin\t1.6.0\t1.7.0\tnew.plugin\n",
			)

		val findings = PlatformDeprecations.findings(entries, setOf("g:a", "g:z"), setOf("platformOld"), emptySet())

		assertEquals(
			listOf(
				"[PLAT-DEPR-001] dependency g:a is deprecated since Platform 1.6.0 and goes in 1.7.0: use g:b",
				"[PLAT-DEPR-001] property platformOld is deprecated since Platform 1.6.0 and goes in 1.7.0: use platformNew",
			),
			findings.map { it.render() },
		)
		assertEquals(entries, entries.map { PlatformDeprecations.decode(PlatformDeprecations.encode(it)) })
	}

	@Test
	fun `a malformed entry fails loudly`() {
		assertThrows(IllegalArgumentException::class.java) { PlatformDeprecations.parse("library\tg:a\t1.6.0\n") }
	}
}
