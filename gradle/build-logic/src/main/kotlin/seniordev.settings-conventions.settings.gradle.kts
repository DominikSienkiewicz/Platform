/*
 * seniordev.settings-conventions
 * ------------------------------
 * Convention plugin dla settings.gradle.kts konsumenta:
 *   - foojay-resolver-convention (lokalny auto-provisioning JDK pod toolchain z java-conventions) — wersja z classpath
 *     build-logic (lustro gradle/catalog), znika hardkod "version 1.0.0" z 3 repo
 *   - dependencyResolutionManagement.repositories: mavenCentral + GitHub Packages (Platform)
 *     z tym samym wiring-iem poświadczeń co dotychczas (gpr.user/gpr.key lub GITHUB_ACTOR/GITHUB_TOKEN)
 *
 * U konsumenta ZOSTAJE (z definicji nie da się przenieść):
 *   - pluginManagement.repositories — potrzebne, żeby w ogóle rozwiązać TEN plugin
 *   - versionCatalogs { from("pl.seniordeveloper:platform-catalog:X") } — to jest pin platformy per repo
 *   - rootProject.name
 */

plugins {
	id("org.gradle.toolchains.foojay-resolver-convention")
}

dependencyResolutionManagement {
	repositories {
		mavenCentral()
		maven {
			name = "GitHubPackages"
			url = uri("https://maven.pkg.github.com/DominikSienkiewicz/Platform")
			credentials {
				username = providers.gradleProperty("gpr.user").orElse(providers.environmentVariable("GITHUB_ACTOR")).orNull
				password = providers.gradleProperty("gpr.key").orElse(providers.environmentVariable("GITHUB_TOKEN")).orNull
			}
		}
	}
}
