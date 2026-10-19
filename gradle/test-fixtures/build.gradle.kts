plugins {
	`java-library`
	`maven-publish`
	id("seniordev.java-conventions")
}

group = "pl.seniordeveloper"
version = providers.gradleProperty("platformVersion").get()

java {
	// 25 nadpisuje toolchain 27 z java-conventions: artefakt ładuje się w Gradle na JDK 25 (README, Requirements).
	toolchain { languageVersion = JavaLanguageVersion.of(25) }
	// Sources i javadoc jar obok binarki: IDE konsumenta pokazuje źródła i przykłady z javadoc bez dekompilacji.
	withSourcesJar()
	withJavadocJar()
}

repositories { mavenCentral() }

// Dependency locking — powtarzalne rozwiązywanie zależności (gradle.lockfile).
// Regeneracja po bumpie BOM-ów/wersji wyżej: ./gradlew dependencies --write-locks
dependencyLocking {
	lockAllConfigurations()
}

dependencies {
	// Natywne platformy Gradle zamiast io.spring.dependency-management — dzięki temu publikowane
	// Gradle Module Metadata jest POPRAWNE (zależności bez wersji są pokryte referencją do platformy,
	// a BOM-y eksportują się tranzytywnie do konsumenta). Wersje = lustro gradle/catalog.
	api(platform(libs.spring.boot.bom))
	api(platform(libs.spring.modulith.bom))
	api(platform(libs.junit.bom))

	api("org.springframework.boot:spring-boot-testcontainers")
	api("org.springframework.boot:spring-boot-test")               // @TestConfiguration
	api("org.testcontainers:testcontainers-postgresql")
	api("org.springframework.modulith:spring-modulith-core")       // ApplicationModules
	api("org.junit.jupiter:junit-jupiter-api")
	// Ollama tylko dla PlatformOllamaContainer — konsument (np. Attestate) dostarcza artefakt sam.
	compileOnly("org.testcontainers:testcontainers-ollama")
	// Parser Liquibase dla AbstractLiquibaseChangelogTest — konsument na Liquibase ma go z własnego startera.
	compileOnly("org.liquibase:liquibase-core")

	testImplementation("org.junit.jupiter:junit-jupiter")
	testImplementation("org.assertj:assertj-core")
	testImplementation("org.liquibase:liquibase-core")
	testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

tasks.withType<Test>().configureEach { useJUnitPlatform() }

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
