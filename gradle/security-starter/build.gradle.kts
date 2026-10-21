plugins {
	`java-library`
	`maven-publish`
	id("seniordev.java-conventions")
	id("seniordev.quality-conventions")
}

group = "pl.seniordeveloper"
version = providers.gradleProperty("platformVersion").get()

java {
	// Sources i javadoc jar obok binarki: IDE konsumenta pokazuje źródła i przykłady z javadoc bez dekompilacji.
	withSourcesJar()
	withJavadocJar()
}

repositories { mavenCentral() }

// Decyzja 28: Platform skanuje się w SonarQube Cloud jak konsumenci (zasada 8). projectKey z fallbacku
// DominikSienkiewicz_<rootProject.name>; job `sonar` w ci.yml biegnie tylko z sekretem SONAR_TOKEN.
pitest {
	targetClasses.set(listOf("pl.seniordeveloper.platform.security.*"))
}

// Dependency locking — powtarzalne rozwiązywanie zależności (gradle.lockfile).
dependencyLocking {
	lockAllConfigurations()
}

dependencies {
	// Natywna platforma Gradle (poprawne Gradle Module Metadata): platform-bom (Boot + podłogi CVE).
	api(platform(libs.platform.bom))

	// Starter wnosi Spring Security do konsumenta (api) + spring-web dla klas CORS. Wersje z BOM-a.
	api("org.springframework.boot:spring-boot-starter-security")
	api("org.springframework:spring-web")
	// Auto-konfiguracja (@AutoConfiguration / @ConditionalOn*) — konsument ma je z Boota, więc compileOnly.
	compileOnly("org.springframework.boot:spring-boot-autoconfigure")
	// Tryb platform.security.mode=jwt (N-CAP-13): resource server deklaruje konsument (zasada 2), starter tylko
	// kompiluje się na nim; PlatformJwtResourceServer ładuje te klasy dopiero, gdy są na classpath.
	compileOnly("org.springframework.boot:spring-boot-starter-security-oauth2-resource-server")
	// Odpowiedzi problem+json piszą wprost do HttpServletResponse; aplikacja servletowa (warunek startera) ma to API.
	compileOnly("jakarta.servlet:jakarta.servlet-api")
	// Konfiguracja annotationProcessor nie dziedziczy BOM-a z api/implementation — trzeba jej podać platformę
	// osobno, inaczej spring-boot-configuration-processor rozwiązuje się bez wersji (build fail).
	annotationProcessor(platform(libs.platform.bom))
	annotationProcessor("org.springframework.boot:spring-boot-configuration-processor")
	testImplementation(platform(libs.platform.bom))
	testImplementation("org.springframework.boot:spring-boot-starter-test")
	testImplementation("jakarta.servlet:jakarta.servlet-api")
	testImplementation("org.springframework:spring-webmvc")
	// ManagementWebSecurityAutoConfiguration w PlatformSecurityBootAutoConfigurationTest; wersja z BOM-a Boota.
	testImplementation("org.springframework.boot:spring-boot-starter-actuator")
	testImplementation("org.springframework.boot:spring-boot-starter-security-oauth2-resource-server")
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

// Repozytorium Maven bez poświadczeń dołączane do GitHub Release (scripts/release-assets.sh, N-SHOW-9).
providers.gradleProperty("platformBundleRepository").orNull?.let { repository ->
	publishing.repositories.maven {
		name = "Bundle"
		url = uri(repository)
	}
}

tasks.withType<Test>().configureEach { useJUnitPlatform() }
