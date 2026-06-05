plugins {
	`java-library`
	`maven-publish`
	id("io.spring.dependency-management") version "1.1.7"
}

group = "pl.seniordeveloper"
version = providers.gradleProperty("platformVersion").getOrElse("1.0.0")

java {
	toolchain { languageVersion = JavaLanguageVersion.of(25) }
}

repositories { mavenCentral() }

// Wersje BOM = lustro gradle/catalog (precompiled/standalone build nie czyta zewnętrznego katalogu).
dependencyManagement {
	imports {
		mavenBom("org.springframework.boot:spring-boot-dependencies:4.0.6")
		mavenBom("org.springframework.modulith:spring-modulith-bom:2.0.6")
	}
}

dependencies {
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
