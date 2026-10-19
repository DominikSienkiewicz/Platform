// Publikowany artefakt z reużywalną infrastrukturą testową backendu (Testcontainers + bazy testów).
// Konsumpcja: testImplementation(libs.platform.test.fixtures)
// Własne convention pluginy z tego repo (D-8): Platform podlega bramkom, które narzuca konsumentom.
// Wewnątrz jednego repo composite build działa; nie przekracza tylko granicy repozytorium.
pluginManagement {
	includeBuild("../build-logic")
}

rootProject.name = "platform-test-fixtures"


dependencyResolutionManagement {
	versionCatalogs {
		create("libs") { from(files("../catalog/libs.versions.toml")) }
	}
}
