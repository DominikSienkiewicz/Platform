plugins {
	`kotlin-dsl`
	`maven-publish`
}

group = "pl.seniordeveloper.gradle"
version = providers.gradleProperty("platformVersion").getOrElse("1.0.0")

// Pin toolchainu na 25, żeby compileJava i compileKotlin celowały w ten sam JVM-target niezależnie
// od ambientowego JDK (lokalnie JDK 26 dawał ostrzeżenie o niespójności 26 vs 25).
java {
	toolchain {
		languageVersion = JavaLanguageVersion.of(25)
	}
}

repositories {
	gradlePluginPortal()
	mavenCentral()
}

// Dependency locking — powtarzalne rozwiązywanie zależności (gradle.lockfile).
// Regeneracja po bumpie którejkolwiek wersji wyżej: ./gradlew dependencies --write-locks
dependencyLocking {
	lockAllConfigurations()
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
	implementation("org.sonarqube:org.sonarqube.gradle.plugin:7.3.1.8318")
	// Settings plugin (toolchain auto-provisioning) — aplikowany przez seniordev.settings-conventions.
	implementation("org.gradle.toolchains:foojay-resolver:1.0.0")

	// Testy configów platformy (guard checkstyle ↔ google-java-format).
	// Checkstyle = lustro toolVersion w seniordev.java-conventions (te same reguły co u konsumenta).
	// JUnit = lustro gradle/catalog (version "junit").
	testImplementation("com.puppycrawl.tools:checkstyle:13.5.0")
	testImplementation(platform("org.junit:junit-bom:6.1.0"))
	testImplementation("org.junit.jupiter:junit-jupiter")
	testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

tasks.withType<Test>().configureEach {
	useJUnitPlatform()
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
