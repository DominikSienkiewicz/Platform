plugins {
	`java-library`
	`maven-publish`
}

group = "pl.seniordeveloper"
version = providers.gradleProperty("platformVersion").getOrElse("1.0.0")

java {
	toolchain { languageVersion = JavaLanguageVersion.of(25) }
}

repositories { mavenCentral() }

// Dependency locking — powtarzalne rozwiązywanie zależności (gradle.lockfile).
dependencyLocking {
	lockAllConfigurations()
}

dependencies {
	// Natywna platforma Gradle (poprawne Gradle Module Metadata). Wersja = lustro gradle/catalog (Boot 4.1.0).
	api(platform("org.springframework.boot:spring-boot-dependencies:4.1.0"))

	// Starter wnosi Spring Security do konsumenta (api) + spring-web dla klas CORS. Wersje z BOM-a.
	api("org.springframework.boot:spring-boot-starter-security")
	api("org.springframework:spring-web")
	// Auto-konfiguracja (@AutoConfiguration / @ConditionalOn*) — konsument ma je z Boota, więc compileOnly.
	compileOnly("org.springframework.boot:spring-boot-autoconfigure")
	// Konfiguracja annotationProcessor nie dziedziczy BOM-a z api/implementation — trzeba jej podać platformę
	// osobno, inaczej spring-boot-configuration-processor rozwiązuje się bez wersji (build fail).
	annotationProcessor(platform("org.springframework.boot:spring-boot-dependencies:4.1.0"))
	annotationProcessor("org.springframework.boot:spring-boot-configuration-processor")
}

val gprOwner = providers.gradleProperty("gpr.owner").orElse(providers.environmentVariable("GPR_OWNER")).getOrElse("DominikSienkiewicz")
val gprRepo = providers.gradleProperty("gpr.repo").orElse(providers.environmentVariable("GPR_REPO")).getOrElse("Platform")

publishing {
	publications {
		create<MavenPublication>("maven") { from(components["java"]) }
		withType<MavenPublication>().configureEach {
			pom {
				licenses {
					license {
						name.set("MIT License")
						url.set("https://github.com/DominikSienkiewicz/Platform/blob/main/LICENSE")
					}
				}
			}
		}
	}
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
