plugins {
	`java-library`
	`maven-publish`
}

group = "pl.seniordeveloper"
version = providers.gradleProperty("platformVersion").get()

java {
	toolchain { languageVersion = JavaLanguageVersion.of(25) }
	// Sources i javadoc jar obok binarki: IDE konsumenta pokazuje źródła i przykłady z javadoc bez dekompilacji.
	withSourcesJar()
	withJavadocJar()
}

repositories { mavenCentral() }

// Dependency locking — powtarzalne rozwiązywanie zależności (gradle.lockfile).
dependencyLocking {
	lockAllConfigurations()
}

dependencies {
	// Natywna platforma Gradle (poprawne Gradle Module Metadata). Wersja z gradle/catalog.
	api(platform(libs.spring.boot.bom))

	// Starter wnosi Spring Security do konsumenta (api) + spring-web dla klas CORS. Wersje z BOM-a.
	api("org.springframework.boot:spring-boot-starter-security")
	api("org.springframework:spring-web")
	// Auto-konfiguracja (@AutoConfiguration / @ConditionalOn*) — konsument ma je z Boota, więc compileOnly.
	compileOnly("org.springframework.boot:spring-boot-autoconfigure")
	// Konfiguracja annotationProcessor nie dziedziczy BOM-a z api/implementation — trzeba jej podać platformę
	// osobno, inaczej spring-boot-configuration-processor rozwiązuje się bez wersji (build fail).
	annotationProcessor(platform(libs.spring.boot.bom))
	annotationProcessor("org.springframework.boot:spring-boot-configuration-processor")
	testImplementation(platform(libs.junit.bom))
	testImplementation("org.springframework.boot:spring-boot-starter-test")
	testImplementation("jakarta.servlet:jakarta.servlet-api")
	testImplementation("org.springframework:spring-webmvc")
	// ManagementWebSecurityAutoConfiguration w PlatformSecurityBootAutoConfigurationTest; wersja z BOM-a Boota.
	testImplementation("org.springframework.boot:spring-boot-starter-actuator")
	testRuntimeOnly("org.junit.platform:junit-platform-launcher")
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

tasks.withType<Test>().configureEach { useJUnitPlatform() }
