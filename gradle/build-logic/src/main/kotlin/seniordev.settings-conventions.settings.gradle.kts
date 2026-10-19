/*
 * seniordev.settings-conventions
 * ------------------------------
 * Convention plugin dla settings.gradle.kts konsumenta:
 *   - foojay-resolver-convention (lokalny auto-provisioning JDK pod toolchain z java-conventions) — wersja z classpath
 *     build-logic (lustro gradle/catalog), znika hardkod wersji foojay w repo konsumentów
 *   - dependencyResolutionManagement.repositories: opcjonalne -PplatformRepository (pierwsze; jedyna droga do
 *     niewydanych zmian, ADR-0003), mavenCentral i GitHub Packages (gpr.user/gpr.key lub GITHUB_ACTOR/GITHUB_TOKEN)
 *   - task `platformDoctor` na root projekcie (N-DX-1): piny, toolchain i coverageMinimum widziane przez Gradle'a
 *   - jedna linia, gdy wydanie Platform jest starsze niż okno wsparcia (N-REL-6, `platform.stalenessNotice=false`)
 *
 * U konsumenta ZOSTAJE (z definicji nie da się przenieść):
 *   - pluginManagement.repositories — potrzebne, żeby w ogóle rozwiązać TEN plugin
 *   - versionCatalogs { from("pl.seniordeveloper:platform-catalog:X") } — to jest pin platformy per repo
 *   - rootProject.name
 */

import org.gradle.api.artifacts.VersionCatalogsExtension
import org.gradle.api.plugins.JavaPluginExtension
import org.gradle.util.GradleVersion
import pl.seniordeveloper.gradle.PlatformDoctor
import pl.seniordeveloper.gradle.PlatformStaleness
import pl.seniordeveloper.gradle.PlatformVersions
import java.time.LocalDate

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

// Okno wsparcia (N-REL-6): jedna linia na build, gdy to wydanie jest starsze niż okno; nigdy błąd.
// -Pplatform.stalenessNotice=false wycisza, -Pplatform.stalenessToday=YYYY-MM-DD tylko dla testów Platform.
if (providers.gradleProperty("platform.stalenessNotice").orNull?.trim() != "false") {
	PlatformStaleness.load()?.let { release ->
		val today = providers.gradleProperty("platform.stalenessToday").orNull?.let(LocalDate::parse) ?: LocalDate.now()
		PlatformStaleness.notice(release, today)?.let { logger.lifecycle(it) }
	}
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

// Akcja konfiguracji taska biegnie przy jego realizacji, po konfiguracji roota: katalog i toolchain są już znane,
// a task dostaje gotowe wartości (configuration cache). Bin platform-doctor woła go z --gradle.
gradle.rootProject {
	tasks.register<PlatformDoctor>("platformDoctor") {
		group = "help"
		description =
			"Diagnoses the Gradle side of a Platform consumer: pins, toolchain and coverageMinimum (docs/consuming.md, Troubleshooting)."
		pluginVersion.set(PlatformVersions.PLATFORM)
		catalogVersion.set(
			project.extensions
				.findByType(VersionCatalogsExtension::class.java)
				?.find("libs")
				?.orElse(null)
				?.findVersion("platform")
				?.orElse(null)
				?.requiredVersion,
		)
		platformVersionProperty.set(project.providers.gradleProperty("platformVersion"))
		coverageMinimum.set(project.providers.gradleProperty("coverageMinimum"))
		toolchainLanguageVersion.set(
			project.extensions
				.findByType(JavaPluginExtension::class.java)
				?.toolchain
				?.languageVersion
				?.orNull
				?.asInt(),
		)
	}
}
