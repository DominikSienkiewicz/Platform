pluginManagement {
	val platformRepository = providers.gradleProperty("platformRepository").orNull
	// Pusta albo z samych spacji wartość liczy się jak brak (N-DX-18): devcontainer przekazuje nieustawioną
	// zmienną hosta jako "", a puste gpr.* w gradle.properties nie może zasłonić GITHUB_ACTOR/GITHUB_TOKEN.
	val gprUser =
		providers
			.gradleProperty("gpr.user")
			.filter { it.isNotBlank() }
			.orElse(providers.environmentVariable("GITHUB_ACTOR").filter { it.isNotBlank() })
			.orNull
	val gprKey =
		providers
			.gradleProperty("gpr.key")
			.filter { it.isNotBlank() }
			.orElse(providers.environmentVariable("GITHUB_TOKEN").filter { it.isNotBlank() })
			.orNull
	// Bez poświadczeń GitHub Packages odpowiada 401, które Gradle chowa pod „plugin not found” (N-DX-2): nazwij
	// przyczynę, zanim pójdzie pierwsze żądanie. Lokalna Platform (-PplatformRepository) i --offline ich nie potrzebują.
	if ((gprUser == null || gprKey == null) && platformRepository == null && !gradle.startParameter.isOffline) {
		throw GradleException(
			"No GitHub Packages credentials, so the Platform plugins cannot resolve. Set gpr.user and gpr.key in " +
				"~/.gradle/gradle.properties, or GITHUB_ACTOR and GITHUB_TOKEN in the environment, with a classic token that " +
				"has the read:packages scope (https://github.com/DominikSienkiewicz/Platform/blob/main/docs/consuming.md#prerequisites). " +
				"To build against a local Platform instead, pass -PplatformRepository.",
		)
	}
	repositories {
		platformRepository?.let { maven { url = uri(it) } }
		gradlePluginPortal()
		mavenCentral()
		maven {
			url = uri("https://maven.pkg.github.com/DominikSienkiewicz/Platform")
			credentials {
				username = gprUser
				password = gprKey
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

rootProject.name = "spring-app"
