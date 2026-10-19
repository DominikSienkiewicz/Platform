package pl.seniordeveloper.gradle

import java.time.LocalDate

/** Jedno oznaczenie kwarantanny w źródłach testów i to, co bramka o nim sądzi. */
data class QuarantineEntry(
	val file: String,
	val line: Int,
	val issue: String?,
	val until: LocalDate?,
)

/**
 * Kwarantanna z terminem (N-REL-13): każde `@Tag("quarantine")` (albo `PlatformTestTags.QUARANTINE`) wymaga w trzech
 * liniach nad sobą komentarza `// quarantine: <issue-url> until YYYY-MM-DD`, więc kwarantanna nie zamienia się
 * w cmentarz testów. Brak komentarza failuje zawsze, przeterminowany wpis — tylko w CI (Decyzja owner'a: stare
 * commity zostają odtwarzalne lokalnie).
 */
object QuarantineRules {
	private val TAG = Regex("""@Tag\(\s*(?:"quarantine"|PlatformTestTags\.QUARANTINE)\s*\)""")
	private val COMMENT = Regex("""//\s*quarantine:\s*(\S+)\s+until\s+(\d{4}-\d{2}-\d{2})""")

	fun scan(
		file: String,
		text: String,
	): List<QuarantineEntry> {
		val lines = text.lines()
		return lines.indices.filter { TAG.containsMatchIn(lines[it]) }.map { index ->
			val comment = (maxOf(0, index - 3) until index).reversed().firstNotNullOfOrNull { COMMENT.find(lines[it]) }
			QuarantineEntry(file, index + 1, comment?.groupValues?.get(1), comment?.groupValues?.get(2)?.let(LocalDate::parse))
		}
	}

	fun missing(entries: List<QuarantineEntry>): List<GateFinding> =
		entries.filter { it.issue == null }.map {
			GateFinding(
				PlatformGates.QUARANTINE_UNTRACKED,
				"${it.file}:${it.line} quarantines a test without \"// quarantine: <issue-url> until YYYY-MM-DD\" in the three lines above",
			)
		}

	fun expired(
		entries: List<QuarantineEntry>,
		today: LocalDate,
	): List<GateFinding> =
		entries.filter { it.until != null && it.until.isBefore(today) }.map {
			GateFinding(
				PlatformGates.QUARANTINE_EXPIRED,
				"${it.file}:${it.line} stayed in quarantine past ${it.until} (${it.issue}): fix the test and remove the tag, " +
					"or extend the date with a reason in the issue",
			)
		}
}
