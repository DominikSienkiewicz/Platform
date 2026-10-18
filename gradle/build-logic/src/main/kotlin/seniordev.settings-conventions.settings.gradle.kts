/*
 * seniordev.settings-conventions
 * ------------------------------
 * Convention plugin dla settings.gradle.kts konsumenta:
 *   - foojay-resolver-convention (lokalny auto-provisioning JDK pod toolchain z java-conventions) — wersja z classpath
 *     build-logic (lustro gradle/catalog), znika hardkod wersji foojay w repo konsumentów
 *   - dependencyResolutionManagement.repositories: opcjonalne -PplatformRepository (pierwsze; jedyna droga do
 *     niewydanych zmian, ADR-0003), mavenCentral i GitHub Packages (gpr.user/gpr.key lub GITHUB_ACTOR/GITHUB_TOKEN)
 *
 * U konsumenta ZOSTAJE (z definicji nie da się przenieść):
 *   - pluginManagement.repositories — potrzebne, żeby w ogóle rozwiązać TEN plugin
 *   - versionCatalogs { from("pl.seniordeveloper:platform-catalog:X") } — to jest pin platformy per repo
 *   - rootProject.name
 */

import org.gradle.util.GradleVersion

plugins {
	id("org.gradle.toolchains.foojay-resolver-convention")
}

// Najstarszy Gradle, na którym TestKit buduje konsumenta (PlatformMinimumGradleFunctionalTest). Starszy dostaje
// komunikat z naprawą zamiast przypadkowego błędu ładowania Kotlin DSL — o ile plugin w ogóle się załaduje.
// Lustro: minimumConsumerGradle w gradle/build-logic/gradle.properties; pilnuje PlatformGradleVersionMirrorTest.
val minimumConsumerGradle: GradleVersion = GradleVersion.version("9.6.1")
if (GradleVersion.current() < minimumConsumerGradle) {
	throw GradleException(
		"Platform requires Gradle ${minimumConsumerGradle.version} or newer, but this build runs " +
			"${GradleVersion.current().version}. Run scripts/platform-bump.sh, which updates the wrapper, or " +
			"./gradlew wrapper --gradle-version ${minimumConsumerGradle.version}.",
	)
}

dependencyResolutionManagement {
	repositories {
		providers.gradleProperty("platformRepository").orNull?.let { repository ->
			maven { url = uri(repository) }
		}
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
