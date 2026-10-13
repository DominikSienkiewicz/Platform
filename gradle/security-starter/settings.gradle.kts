// Publikowany starter: parametryzowalny SecurityFilterChain + CORS (platform.security.* / platform.cors.*).
// Konsumpcja: implementation(libs.platform.security.starter)
rootProject.name = "platform-security-starter"


dependencyResolutionManagement {
	versionCatalogs {
		create("libs") { from(files("../catalog/libs.versions.toml")) }
	}
}
