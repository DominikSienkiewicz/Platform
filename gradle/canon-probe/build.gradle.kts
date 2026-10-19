import java.util.Properties

// BOM-y i nadpisania ze spring-modulith-conventions, CycloneDX (tylko runtimeClasspath) z quality-conventions.
plugins {
	id("seniordev.spring-modulith-conventions")
	id("seniordev.quality-conventions")
}

// Każdy alias biblioteki z katalogu, przez API katalogu, więc żadna wersja nie żyje poza kanonem (zasada 1):
// z jawną wersją rozwiązuje się do niej, bez wersji do wersji z BOM-ów. BOM-y wchodzą jako platform(), rozpoznane
// po aliasie (`spring-boot-bom` to artefakt spring-boot-dependencies). Artefakty pl.seniordeveloper mają celowo
// nierozwiązywalny placeholder wersji i nie są zależnością zewnętrzną.
val canon = extensions.getByType<VersionCatalogsExtension>().named("libs")

// platform-bom skanowanego commita jako platforma Gradle, w wersji z gradle/bom/gradle.properties (canon-cve-scan.yml
// publikuje go do Maven local), żeby jego podłogi CVE trafiły do SBOM-u niezależnie od importu w konwencjach.
// Na b6877bf probe nie miał skąd go wziąć (nie ma go w Maven Central) i Grype dostał Jacksona 3.1.5 z Boota
// zamiast podłogi 3.1.8. Starszy tag bez gradle/bom importuje BOM-y Springa w konwencjach.
// Properties z importu: w skrypcie z pluginem Java `java` to rozszerzenie `java { }`, więc `java.util` się nie kompiluje.
val platformBomVersion =
	file(providers.gradleProperty("canonRoot").get() + "/gradle/bom/gradle.properties")
		.takeIf { it.isFile }
		?.let { properties -> Properties().apply { properties.inputStream().use { load(it) } }.getProperty("platformVersion") }

dependencies {
	platformBomVersion?.let { implementation(platform("pl.seniordeveloper:platform-bom:$it")) }
	canon.libraryAliases
		.map { alias -> alias to canon.findLibrary(alias).get().get() }
		.filter { (_, library) -> library.group != "pl.seniordeveloper" }
		.forEach { (alias, library) -> if (alias.endsWith("bom")) implementation(platform(library)) else implementation(library) }
}
