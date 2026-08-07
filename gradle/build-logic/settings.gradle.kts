// build-logic = osobny build Gradle publikujący convention plugins (precompiled script plugins)
// jako artefakt Maven. Konsumowany przez 3 repo (Attestate / SkillSprintPlus / BookOfStyling)
// przez `pluginManagement { repositories { maven(GitHub Packages) } }`.
rootProject.name = "build-logic"

// Wersje narzędzi bierzemy wprost z kanonu (gradle/catalog/libs.versions.toml) zamiast trzymać
// ich lustro w build.gradle.kts. Katalog dołączamy z pliku, bo w czasie kompilacji build-logic
// opublikowany artefakt platform-catalog jeszcze nie istnieje.
dependencyResolutionManagement {
	versionCatalogs {
		create("libs") {
			from(files("../catalog/libs.versions.toml"))
		}
	}
}
