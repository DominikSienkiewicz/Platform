// Publikowany artefakt z reużywalną infrastrukturą testową backendu (Testcontainers + bazy testów).
// Konsumpcja: testImplementation(libs.platform.test.fixtures)
rootProject.name = "platform-test-fixtures"


dependencyResolutionManagement {
	versionCatalogs {
		create("libs") { from(files("../catalog/libs.versions.toml")) }
	}
}
