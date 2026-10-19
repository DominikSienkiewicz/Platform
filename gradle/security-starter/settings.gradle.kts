// Publikowany starter: parametryzowalny SecurityFilterChain + CORS (platform.security.* / platform.cors.*).
// Konsumpcja: implementation(libs.platform.security.starter)
// Własne convention pluginy z tego repo (D-8): Platform podlega bramkom, które narzuca konsumentom.
// Wewnątrz jednego repo composite build działa; nie przekracza tylko granicy repozytorium.
pluginManagement {
	includeBuild("../build-logic")
}

rootProject.name = "platform-security-starter"


dependencyResolutionManagement {
	versionCatalogs {
		create("libs") { from(files("../catalog/libs.versions.toml")) }
	}
}
