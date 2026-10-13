pluginManagement {
	repositories {
		providers.gradleProperty("platformRepository").orNull?.let { maven { url = uri(it) } }
		gradlePluginPortal()
		mavenCentral()
		maven {
			url = uri("https://maven.pkg.github.com/DominikSienkiewicz/Platform")
			credentials {
				username = providers.gradleProperty("gpr.user").orElse(providers.environmentVariable("GITHUB_ACTOR")).orNull
				password = providers.gradleProperty("gpr.key").orElse(providers.environmentVariable("GITHUB_TOKEN")).orNull
			}
		}
	}
}

plugins {
	id("seniordev.settings-conventions") version providers.gradleProperty("platformVersion").get()
}

dependencyResolutionManagement {
	versionCatalogs {
		create("libs") {
			from("pl.seniordeveloper:platform-catalog:${providers.gradleProperty("platformVersion").get()}")
		}
	}
}

rootProject.name = "java-library"
