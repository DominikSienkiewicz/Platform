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

dependencies {
	// Natywne platformy Gradle zamiast io.spring.dependency-management — dzięki temu publikowane
	// Gradle Module Metadata jest POPRAWNE (zależności bez wersji są pokryte referencją do platformy,
	// a BOM-y eksportują się tranzytywnie do konsumenta). Wersje = lustro gradle/catalog.
	api(platform("org.springframework.boot:spring-boot-dependencies:4.0.6"))
	api(platform("org.springframework.modulith:spring-modulith-bom:2.0.6"))

	api("org.springframework.boot:spring-boot-testcontainers")
	api("org.springframework.boot:spring-boot-test")               // @TestConfiguration
	api("org.testcontainers:testcontainers-postgresql")
	api("org.springframework.modulith:spring-modulith-core")       // ApplicationModules
	api("org.junit.jupiter:junit-jupiter-api")
	// Ollama tylko dla PlatformOllamaContainer — konsument (np. Attestate) dostarcza artefakt sam.
	compileOnly("org.testcontainers:testcontainers-ollama")
}

val gprOwner = providers.gradleProperty("gpr.owner").orElse(providers.environmentVariable("GPR_OWNER")).getOrElse("DominikSienkiewicz")
val gprRepo = providers.gradleProperty("gpr.repo").orElse(providers.environmentVariable("GPR_REPO")).getOrElse("Platform")

publishing {
	publications {
		create<MavenPublication>("maven") { from(components["java"]) }
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
