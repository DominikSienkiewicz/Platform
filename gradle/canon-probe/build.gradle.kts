// BOM-y i nadpisania ze spring-modulith-conventions, CycloneDX (tylko runtimeClasspath) z quality-conventions.
plugins {
	id("seniordev.spring-modulith-conventions")
	id("seniordev.quality-conventions")
}

// Każdy alias biblioteki z katalogu, przez API katalogu, więc żadna wersja nie żyje poza kanonem (zasada 1):
// z jawną wersją rozwiązuje się do niej, bez wersji do wersji z BOM-ów. BOM-y wchodzą jako platform().
// Artefakty pl.seniordeveloper mają celowo nierozwiązywalny placeholder wersji i nie są zależnością zewnętrzną.
val canon = extensions.getByType<VersionCatalogsExtension>().named("libs")
dependencies {
	canon.libraryAliases
		.map { canon.findLibrary(it).get().get() }
		.filter { it.group != "pl.seniordeveloper" }
		.forEach { library -> if (library.name.endsWith("bom")) implementation(platform(library)) else implementation(library) }
}
