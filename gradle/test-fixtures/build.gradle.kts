plugins {
	`java-library`
	`maven-publish`
	id("seniordev.java-conventions")
	id("seniordev.quality-conventions")
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

// Decyzja 28: Platform skanuje się w SonarQube Cloud jak konsumenci (zasada 8). projectKey z fallbacku
// DominikSienkiewicz_<rootProject.name>; job `sonar` w ci.yml biegnie tylko z sekretem SONAR_TOKEN.
pitest {
	targetClasses.set(listOf("pl.seniordeveloper.platform.testing.*"))
}

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
	// AbstractOpenApiContractTest: mappingi Spring MVC i spec JSON/YAML. Konsument z REST API ma je z własnych
	// starterów (webmvc, Jackson); YAML tylko, gdy jego spec jest w YAML-u.
	compileOnly("org.springframework:spring-webmvc")
	compileOnly("jakarta.servlet:jakarta.servlet-api")
	compileOnly("tools.jackson.core:jackson-databind")
	compileOnly("tools.jackson.dataformat:jackson-dataformat-yaml")
	// PlatformArchRules i HexagonalRules: ArchUnit konsument ma z seniordev.spring-modulith-conventions albo z libs.
	compileOnly(libs.archunit.junit5)
	// AbstractModulithDocumentationTest: Documenter jest w spring-modulith-docs, który daje spring-modulith-starter-test.
	compileOnly("org.springframework.modulith:spring-modulith-docs")

	testImplementation("org.junit.jupiter:junit-jupiter")
	testImplementation("org.assertj:assertj-core")
	testImplementation("org.liquibase:liquibase-core")
	testImplementation("org.springframework:spring-webmvc")
	testImplementation("jakarta.servlet:jakarta.servlet-api")
	testImplementation("tools.jackson.core:jackson-databind")
	testImplementation("tools.jackson.dataformat:jackson-dataformat-yaml")
	testImplementation(libs.archunit.junit5)
	testImplementation("org.springframework.modulith:spring-modulith-docs")
	testImplementation("org.springframework:spring-tx")
	testImplementation("jakarta.persistence:jakarta.persistence-api")
	testImplementation("org.junit.jupiter:junit-jupiter-params")
	// SharedPostgresContainerIT: dwa konteksty Boota z DataSource na wspólnym kontenerze.
	testImplementation("org.springframework.boot:spring-boot-starter-jdbc")
	testRuntimeOnly("org.postgresql:postgresql")
	// AbstractSchemaValidationIT i szablony templates/db: aplikacja z Modulith JPA migrowana Liquibase albo Flyway.
	testImplementation("org.springframework.boot:spring-boot-starter-data-jpa")
	testImplementation("org.springframework.modulith:spring-modulith-starter-jpa")
	testImplementation("org.springframework.boot:spring-boot-starter-liquibase")
	testImplementation("org.springframework.boot:spring-boot-starter-flyway")
	testRuntimeOnly("org.flywaydb:flyway-database-postgresql")
	testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

tasks.withType<Test>().configureEach { useJUnitPlatform() }

// ModulithEventPublicationSchemaIT czyta kanoniczne migracje z templates/db, nie z kopii w zasobach testu.
val platformTemplates = layout.projectDirectory.dir("../../templates")
tasks.test {
	inputs.dir(platformTemplates.dir("db")).withPropertyName("dbTemplates").withPathSensitivity(PathSensitivity.RELATIVE)
	systemProperty("platform.templates.dir", platformTemplates.asFile.absolutePath)
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

// Repozytorium Maven bez poświadczeń dołączane do GitHub Release (scripts/release-assets.sh, N-SHOW-9).
providers.gradleProperty("platformBundleRepository").orNull?.let { repository ->
	publishing.repositories.maven {
		name = "Bundle"
		url = uri(repository)
	}
}
