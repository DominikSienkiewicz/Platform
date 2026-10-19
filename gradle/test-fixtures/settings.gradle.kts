// Publikowany artefakt z reużywalną infrastrukturą testową backendu (Testcontainers + bazy testów).
// Konsumpcja: testImplementation(libs.platform.test.fixtures)
// Własne convention pluginy z tego repo (D-8): Platform podlega bramkom, które narzuca konsumentom.
// Wewnątrz jednego repo composite build działa; nie przekracza tylko granicy repozytorium.
pluginManagement {
	// publishFunctionalTestFixtures w build-logic (N-CAP-14) publikuje ten moduł do repozytorium TestKit z wnętrza
	// buildu build-logic: wtedy konwencje pochodzą z tego repozytorium, gdzie build-logic opublikował je chwilę
	// wcześniej, a nie z includeBuild, który kompilowałby build-logic drugi raz na tych samych katalogach build/.
	val functionalTestRepository = providers.gradleProperty("functionalTestRepository").orNull
	if (functionalTestRepository == null) {
		includeBuild("../build-logic")
	} else {
		repositories {
			maven { url = uri(functionalTestRepository) }
			gradlePluginPortal()
			mavenCentral()
		}
		val platformVersion = providers.gradleProperty("platformVersion").get()
		resolutionStrategy.eachPlugin {
			if (requested.id.namespace == "seniordev") useVersion(platformVersion)
		}
	}
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
