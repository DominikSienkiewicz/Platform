package pl.seniordeveloper.gradle

/** Wpis kanału deprecacji (N-REL-9): co, od którego wydania, kiedy zniknie i czym zastąpić. */
data class Deprecation(
	val kind: String,
	val id: String,
	val since: String,
	val removeIn: String,
	val replacement: String,
)

/**
 * Kanał deprecacji Platform: platform-deprecations.tsv w zasobach pluginu, `rodzaj<TAB>id<TAB>od<TAB>usunięcie<TAB>zamiennik`.
 * Rodzaje: `dependency` (group:name), `property` (właściwość Gradle) i `plugin` (id pluginu). Polityka: deprecacja
 * w MINOR N, usunięcie najwcześniej w N+1, oba w CHANGELOG (Decyzja 2).
 */
object PlatformDeprecations {
	const val RESOURCE = "platform-deprecations.tsv"
	val KINDS = setOf("dependency", "property", "plugin")

	fun parse(tsv: String): List<Deprecation> =
		tsv
			.lineSequence()
			.map { it.trimEnd() }
			.filter { it.isNotEmpty() && !it.startsWith("#") }
			.map { line ->
				val fields = line.split('\t')
				require(fields.size == 5 && fields[0] in KINDS) { "$RESOURCE: malformed entry '$line'" }
				Deprecation(fields[0], fields[1], fields[2], fields[3], fields[4])
			}.toList()

	fun load(): List<Deprecation> =
		PlatformDeprecations::class.java.classLoader
			.getResourceAsStream(RESOURCE)
			?.bufferedReader()
			?.use { parse(it.readText()) }
			.orEmpty()

	fun findings(
		entries: List<Deprecation>,
		declaredModules: Set<String>,
		propertiesSet: Set<String>,
		pluginsApplied: Set<String>,
	): List<GateFinding> =
		entries
			.filter { entry ->
				when (entry.kind) {
					"dependency" -> entry.id in declaredModules
					"property" -> entry.id in propertiesSet
					else -> entry.id in pluginsApplied
				}
			}.map { entry ->
				GateFinding(
					PlatformGates.DEPRECATED,
					"${entry.kind} ${entry.id} is deprecated since Platform ${entry.since} and goes in ${entry.removeIn}: " +
						"use ${entry.replacement}",
				)
			}

	fun encode(entry: Deprecation): String = listOf(entry.kind, entry.id, entry.since, entry.removeIn, entry.replacement).joinToString("\t")

	fun decode(value: String): Deprecation = parse(value).single()
}
