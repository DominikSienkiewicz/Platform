pluginManagement {
	repositories {
		gradlePluginPortal()
		maven {
			name = "GitHubPackages"
			url = uri("https://maven.pkg.github.com/DominikSienkiewicz/Platform")
			// read:packages, see https://github.com/DominikSienkiewicz/Platform/blob/main/docs/consuming.md#prerequisites
		}
	}
}

plugins {
	id("seniordev.settings-conventions") version "2.0.0"
}
