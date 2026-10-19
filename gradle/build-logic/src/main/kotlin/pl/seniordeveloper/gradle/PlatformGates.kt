package pl.seniordeveloper.gradle

/**
 * Stabilne kody bramek Platform (N-SHOW-8). Każdy kod ma kotwicę w docs/gates.md, a link wskazuje wersję docs
 * z wydania, które zgłosiło błąd, nie `main`. Kod raz wycofany nie wraca z innym znaczeniem.
 */
object PlatformGates {
	const val DEP_NOT_IN_CATALOG = "PLAT-DEP-001"
	const val DEP_DIFFERS_FROM_CANON = "PLAT-DEP-002"
	const val DEP_BOM_MANAGED = "PLAT-DEP-003"
	const val DEP_CATALOG_OVERRIDE = "PLAT-DEP-004"
	const val DEP_NO_CATALOG = "PLAT-DEP-005"
	const val PIN_DIVERGE = "PLAT-PIN-001"
	const val IMAGE_OLDER_JAVA = "PLAT-IMG-001"
	const val COVERAGE_NO_DATA = "PLAT-COV-001"
	const val COVERAGE_INVALID = "PLAT-COV-002"
	const val DEPRECATED = "PLAT-DEPR-001"
	const val QUARANTINE_UNTRACKED = "PLAT-QUA-001"
	const val QUARANTINE_EXPIRED = "PLAT-QUA-002"

	fun link(
		code: String,
		version: String = PlatformVersions.PLATFORM,
	): String = "https://github.com/DominikSienkiewicz/Platform/blob/v$version/docs/gates.md#${code.lowercase()}"

	fun line(
		code: String,
		text: String,
	): String = "[$code] $text"

	/** Jeden link na kod, w kolejności kodów — stopka komunikatu bramki. */
	fun footer(codes: Collection<String>): String = codes.distinct().sorted().joinToString("\n") { "  $it: ${link(it)}" }
}
