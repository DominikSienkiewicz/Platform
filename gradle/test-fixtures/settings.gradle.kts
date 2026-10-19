// Publikowany artefakt z reużywalną infrastrukturą testową backendu (Testcontainers + bazy testów).
// Konsumpcja: testImplementation(libs.platform.test.fixtures)
// Własne convention pluginy z tego repo (D-8): Platform podlega bramkom, które narzuca konsumentom.
// Wewnątrz jednego repo composite build działa; nie przekracza tylko granicy repozytorium.
pluginManagement {
	includeBuild("../build-logic")
}

rootProject.name = "platform-test-fixtures"


// platform-bom z tego samego repo zamiast osobnych BOM-ów (N-CAP-12); publikowane metadane wskazują
// pl.seniordeveloper:platform-bom w wersji platformVersion, jak u konsumenta.
includeBuild("../bom")

dependencyResolutionManagement {
	versionCatalogs {
		create("libs") {
			from(files("../catalog/libs.versions.toml"))
			// Jak w publikowanym katalogu: aliasy z version.ref = "platform" biorą platformVersion.
			version("platform", providers.gradleProperty("platformVersion").get())
		}
	}
}
