pluginManagement {
	repositories {
		gradlePluginPortal()
		maven {
			name = "GitHubPackages"
			url = uri("https://maven.pkg.github.com/SeniorDeveloper-pl-Dominik-Sienkiewicz/Platform")
			// read:packages, see https://github.com/SeniorDeveloper-pl-Dominik-Sienkiewicz/Platform/blob/main/docs/consuming.md#prerequisites
		}
	}
}

plugins {
	id("seniordev.settings-conventions") version "2.0.0"
}
