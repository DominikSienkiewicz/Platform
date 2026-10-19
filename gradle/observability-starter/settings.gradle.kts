// Publikowany starter: wspólna baza actuatora, metryk i tracingu (platform.observability.*), N-CAP-4.
// Konsumpcja: implementation(libs.platform.observability.starter)
// Własne convention pluginy z tego repo (D-8): Platform podlega bramkom, które narzuca konsumentom.
// Wewnątrz jednego repo composite build działa; nie przekracza tylko granicy repozytorium.
pluginManagement {
	includeBuild("../build-logic")
}

rootProject.name = "platform-observability-starter"


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
