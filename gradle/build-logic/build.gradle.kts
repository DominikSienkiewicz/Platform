plugins {
	`kotlin-dsl`
	`maven-publish`
}

group = "pl.seniordeveloper.gradle"
version = providers.gradleProperty("platformVersion").getOrElse("1.0.0")

repositories {
	gradlePluginPortal()
	mavenCentral()
}

dependencies {
	// Pluginy aplikowane WEWNĄTRZ convention pluginów muszą być na classpath build-logic
	// jako zwykłe zależności (marker-artefakty pluginów). Wersje = lustro gradle/catalog
	// (jedyna świadoma duplikacja — patrz README, sekcja "Dlaczego wersje są w dwóch miejscach").
	implementation("io.spring.gradle:dependency-management-plugin:1.1.7")
	implementation("com.diffplug.spotless:spotless-plugin-gradle:8.6.0")
	implementation("com.github.spotbugs.snom:spotbugs-gradle-plugin:6.5.5")
	implementation("info.solidsoft.gradle.pitest:gradle-pitest-plugin:1.19.0")
	implementation("org.cyclonedx:cyclonedx-gradle-plugin:3.2.4")
}

// --- Publikacja do GitHub Packages (Maven) ---
val gprOwner = providers.gradleProperty("gpr.owner").orElse(providers.environmentVariable("GPR_OWNER")).getOrElse("DominikSienkiewicz")
val gprRepo = providers.gradleProperty("gpr.repo").orElse(providers.environmentVariable("GPR_REPO")).getOrElse("Platform")

publishing {
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
