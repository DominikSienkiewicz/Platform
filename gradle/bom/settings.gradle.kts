// platform-bom (N-CAP-12): java-platform z importami BOM-ów i ograniczeniami, których katalog TOML nie wyrazi.
// Wersje z tego samego libs.versions.toml; `platform` = platformVersion jak w publikowanym katalogu.
rootProject.name = "platform-bom"

dependencyResolutionManagement {
	versionCatalogs {
		create("libs") {
			from(files("../catalog/libs.versions.toml"))
			version("platform", providers.gradleProperty("platformVersion").get())
		}
	}
}
