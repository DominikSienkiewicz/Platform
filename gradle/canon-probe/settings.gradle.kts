// canon-probe = konsument kanonu Platform budowany WYŁĄCZNIE przez canon-cve-scan.yml. Convention pluginy
// idą ze źródeł (includeBuild), katalog z pliku, więc skan dowolnego taga nie potrzebuje opublikowanych
// artefaktów. -PcanonRoot wskazuje checkout, którego kanon skanujemy (może być starszym tagiem).
pluginManagement {
	includeBuild(providers.gradleProperty("canonRoot").get() + "/gradle/build-logic")
	repositories {
		gradlePluginPortal()
		mavenCentral()
	}
}

dependencyResolutionManagement {
	repositories {
		mavenCentral()
	}
	versionCatalogs {
		create("libs") {
			from(files(providers.gradleProperty("canonRoot").get() + "/gradle/catalog/libs.versions.toml"))
		}
	}
}

rootProject.name = "canon-probe"
