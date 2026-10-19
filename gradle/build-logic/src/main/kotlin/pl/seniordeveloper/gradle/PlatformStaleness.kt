package pl.seniordeveloper.gradle

import java.time.LocalDate
import java.time.format.DateTimeParseException
import java.time.temporal.ChronoUnit
import java.util.Properties

/** Wydanie Platform, z którego pochodzi ten plugin (zasób `platform-release.properties`, generowany w build-logic). */
data class PlatformRelease(
	val version: String,
	val releasedAt: LocalDate,
)

/**
 * Okno wsparcia (N-REL-6, RELEASING.md „Support policy”): poprawki dostaje tylko najnowszy MINOR, a pin może zostać
 * najwyżej 3 wydania albo [WINDOW_DAYS] dni w tyle. Plugin zna tylko własną datę, więc liczy dni; nigdy nie failuje
 * builda, bo bramka zależna od czasu zrobiłaby stare commity nieodtwarzalnymi.
 */
object PlatformStaleness {
	const val WINDOW_DAYS = 60L
	const val RESOURCE = "platform-release.properties"

	fun load(): PlatformRelease? =
		PlatformStaleness::class.java.classLoader
			.getResourceAsStream(RESOURCE)
			?.use { stream -> Properties().apply { load(stream) } }
			?.let { parse(it.getProperty("version").orEmpty(), it.getProperty("releasedAt").orEmpty()) }

	fun parse(
		version: String,
		releasedAt: String,
	): PlatformRelease? {
		if (version.isBlank() || releasedAt.isBlank()) return null
		return try {
			PlatformRelease(version, LocalDate.parse(releasedAt))
		} catch (_: DateTimeParseException) {
			null
		}
	}

	fun notice(
		release: PlatformRelease,
		today: LocalDate,
	): String? {
		val age = ChronoUnit.DAYS.between(release.releasedAt, today)
		if (age <= WINDOW_DAYS) return null
		return "Platform ${release.version} was released $age days ago (${release.releasedAt}); the support window is " +
			"$WINDOW_DAYS days or 3 releases (RELEASING.md, Support policy). Run scripts/platform-bump.sh, or silence this " +
			"notice with -Pplatform.stalenessNotice=false."
	}
}
