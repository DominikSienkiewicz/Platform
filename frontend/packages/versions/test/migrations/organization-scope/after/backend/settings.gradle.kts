pluginManagement {
	repositories {
		gradlePluginPortal()
		maven {
			name = "GitHubPackages"
			url = uri("https://maven.pkg.github.com/SeniorDeveloper-pl-Dominik-Sienkiewicz/Platform")
			// read:packages, see https://github.com/DominikSienkiewicz/Platform/blob/main/docs/consuming.md#prerequisites
			credentials {
				username = providers.gradleProperty("gpr.user").orNull
				password = providers.gradleProperty("gpr.key").orNull ?: error(
					"No GitHub Packages credentials (https://github.com/SeniorDeveloper-pl-Dominik-Sienkiewicz/Platform/blob/main/docs/consuming.md#prerequisites)",
				)
			}
		}
	}
}

plugins {
	id("seniordev.settings-conventions") version "2.0.0"
}

/* The settings plugin of 1.x resolves from https://maven.pkg.github.com/DominikSienkiewicz/Platform,
   which answers 404 since the transfer. */
dependencyResolutionManagement {
	repositories {
		// Stopgap: DominikSienkiewicz/Platform no longer serves the catalog and the starters.
		maven {
			name = "PlatformOrganizationPackages"
			url = uri("https://maven.pkg.github.com/SeniorDeveloper-pl-Dominik-Sienkiewicz/Platform") // old URL: 404
		}
	}
}
