package pl.seniordeveloper.gradle

/** Zadeklarowana zależność albo constraint z jawną wersją, w kubełku, który podlega governance. */
data class DeclaredDependency(
	val key: String,
	val version: String,
	val bucket: String,
) {
	fun encode(): String = "$key|$version|$bucket"

	companion object {
		fun decode(value: String): DeclaredDependency = value.split('|', limit = 3).let { DeclaredDependency(it[0], it[1], it[2]) }
	}
}

/** Jedno naruszenie bramki: kod z PlatformGates i tekst po angielsku (Decyzja 8). */
data class GateFinding(
	val code: String,
	val text: String,
) {
	fun render(): String = PlatformGates.line(code, text)
}

/** Wpis kanonu osadzonego w pluginie: wersja (pusta = zarządzana BOM-ami) i alias `libs.…`. */
data class CanonEntry(
	val version: String,
	val accessor: String,
)

/**
 * Reguły platformDependencyCheck bez Gradle'a, testowane jednostkowo (DependencyGovernanceTest). Kanonem jest
 * plik platform-canon.tsv osadzony w pluginie (E1-6), nie katalog `libs` konsumenta.
 */
object DependencyGovernance {
	fun parseCanon(tsv: String): Map<String, CanonEntry> =
		tsv
			.lineSequence()
			.filter { it.isNotBlank() }
			.map { it.split('\t') }
			.associate { (key, version, accessor) -> key to CanonEntry(version, accessor) }

	/** Klucze bez wpisu w kanonie: tylko dla nich akcja taska pyta BOM-y o zarządzaną wersję. */
	fun uncataloged(
		declared: List<DeclaredDependency>,
		canon: Map<String, CanonEntry>,
	): Set<String> = declared.map { it.key }.filterNot { it in canon }.toSet()

	/**
	 * Moduły, które z wersją dokłada sam Gradle, nie konsument: przy JUnit Platform Gradle 9 dopisuje do testRuntimeOnly
	 * junit-platform-launcher w wersji, którą sam wybiera (z junit-bom zadeklarowanego wprost, inaczej własną domyślną).
	 * Rozwiązanie wyrównuje go i tak do JUnit z BOM-ów Platform, więc bramka go nie ocenia.
	 */
	val GRADLE_INJECTED: Set<String> = setOf("org.junit.platform:junit-platform-launcher")

	fun violations(
		declared: List<DeclaredDependency>,
		canon: Map<String, CanonEntry>,
		bomManaged: Map<String, String>,
		exempt: Set<String> = emptySet(),
	): List<GateFinding> =
		declared.filterNot { it.key in exempt }.mapNotNull { dependency ->
			val entry = canon[dependency.key]
			val declaredAs = "${dependency.key}:${dependency.version} (${dependency.bucket})"
			when {
				entry != null && entry.version == dependency.version -> {
					null
				}

				entry != null && entry.version.isNotEmpty() -> {
					GateFinding(
						PlatformGates.DEP_DIFFERS_FROM_CANON,
						"$declaredAs — Platform canon is ${entry.version}: declare it as ${entry.accessor}",
					)
				}

				entry != null -> {
					GateFinding(
						PlatformGates.DEP_BOM_MANAGED,
						"$declaredAs — managed by the Platform BOMs: remove the explicit version and declare it as ${entry.accessor}",
					)
				}

				bomManaged[dependency.key] != null -> {
					GateFinding(
						PlatformGates.DEP_BOM_MANAGED,
						"$declaredAs — the Platform BOMs manage it at ${bomManaged[dependency.key]}: remove the explicit version. " +
							"To run another version on purpose, override the BOM property instead, which platformBomOverrideCheck reports",
					)
				}

				else -> {
					GateFinding(
						PlatformGates.DEP_NOT_IN_CATALOG,
						"$declaredAs — not in the Platform catalog and no Platform BOM manages it: add it to " +
							"gradle/catalog/libs.versions.toml in DominikSienkiewicz/Platform, release, and bump the Platform pin",
					)
				}
			}
		}

	/**
	 * Wersje, które katalog `libs` konsumenta podaje inaczej niż kanon osadzony w pluginie — `version(...)` po
	 * `from(...)` w settings. Artefakty pl.seniordeveloper pomija: ich rozjazd zgłasza platformPinCheck.
	 */
	fun catalogOverrides(
		consumerCatalog: Map<String, String>,
		canon: Map<String, CanonEntry>,
	): List<GateFinding> =
		consumerCatalog
			.filterKeys { !it.startsWith("pl.seniordeveloper:") }
			.mapNotNull { (key, version) ->
				val entry = canon[key] ?: return@mapNotNull null
				if (entry.version == version) {
					null
				} else {
					GateFinding(
						PlatformGates.DEP_CATALOG_OVERRIDE,
						"the libs catalog sets $key to ${version.ifEmpty { "no version" }}, but the Platform canon is " +
							"${entry.version.ifEmpty { "BOM-managed" }}: remove the version(...) override of ${entry.accessor} " +
							"from settings.gradle.kts",
					)
				}
			}.sortedBy { it.text }

	fun noCatalog(): GateFinding =
		GateFinding(
			PlatformGates.DEP_NO_CATALOG,
			"seniordev.java-conventions requires a 'libs' version catalog from platform-catalog: declare " +
				"versionCatalogs { create(\"libs\") { from(\"pl.seniordeveloper:platform-catalog:<version>\") } } in settings.gradle.kts",
		)

	/** Raport Markdown (N-DX-10): plik w build/reports/platform i $GITHUB_STEP_SUMMARY w Actions. */
	fun report(
		project: String,
		findings: List<GateFinding>,
		deprecations: List<GateFinding>,
	): String =
		buildString {
			appendLine("### platformDependencyCheck — $project")
			appendLine()
			if (findings.isEmpty()) {
				appendLine("Every explicit dependency version matches the Platform canon.")
			} else {
				appendLine("| Code | Finding |")
				appendLine("|---|---|")
				findings.forEach { appendLine("| [${it.code}](${PlatformGates.link(it.code)}) | ${it.text.replace("|", "\\|")} |") }
			}
			if (deprecations.isNotEmpty()) {
				appendLine()
				appendLine("Deprecated, still working:")
				appendLine()
				deprecations.forEach { appendLine("- [${it.code}](${PlatformGates.link(it.code)}) ${it.text}") }
			}
		}
}
