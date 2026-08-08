plugins {
	`version-catalog`
	`maven-publish`
}

group = "pl.seniordeveloper"
version = providers.gradleProperty("platformVersion").getOrElse("1.5.23")

// Dependency locking — spójnie z build-logic/test-fixtures/security-starter. Ten moduł publikuje
// metadane i nie ma grafu zależności, więc lockfile jest pusty; trzymamy go, żeby każdy moduł
// Gradle w repo miał jednakowy, weryfikowalny stan rozwiązywania zależności.
dependencyLocking {
	lockAllConfigurations()
}

catalog {
	versionCatalog {
		// KANON wersji backendu = plain-plik libs.versions.toml (edytowalny, Renovate-friendly,
		// symetryczny z FE frontend/packages/versions/versions.json).
		from(files("libs.versions.toml"))

		// Dynamiczny pin platformy — NIE do wyrażenia w statycznym TOML. Nadpisuje placeholder z TOML;
		// wpisy z version.ref="platform" (platform-test-fixtures, platform-security-starter,
		// convention pluginy) podchwytują tę wstrzykniętą wartość. Publish ustawia ją przez -PplatformVersion.
		version("platform", providers.gradleProperty("platformVersion").getOrElse("1.5.23"))
	}
}

val gprOwner = providers.gradleProperty("gpr.owner").orElse(providers.environmentVariable("GPR_OWNER")).getOrElse("DominikSienkiewicz")
val gprRepo = providers.gradleProperty("gpr.repo").orElse(providers.environmentVariable("GPR_REPO")).getOrElse("Platform")

publishing {
	publications {
		create<MavenPublication>("maven") {
			from(components["versionCatalog"])
		}
		withType<MavenPublication>().configureEach {
			pom {
				licenses {
					license {
						name.set("MIT License")
						url.set("https://github.com/DominikSienkiewicz/Platform/blob/main/LICENSE")
					}
				}
			}
		}
	}
	repositories {
		maven {
			name = "GitHubPackages"
			url = uri("https://maven.pkg.github.com/$gprOwner/$gprRepo")
			credentials {
				username = providers.gradleProperty("gpr.user").orElse(providers.environmentVariable("GITHUB_ACTOR")).orNull
				password = providers.gradleProperty("gpr.key").orElse(providers.environmentVariable("GITHUB_TOKEN")).orNull
			}
		}
	}
}
