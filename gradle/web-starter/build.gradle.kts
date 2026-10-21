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

// Decyzja 28: jak pozostałe moduły Java Platform — SonarQube Cloud z quality-conventions.
pitest {
	targetClasses.set(listOf("pl.seniordeveloper.platform.web.*"))
}

// Dependency locking — powtarzalne rozwiązywanie zależności (gradle.lockfile).
dependencyLocking {
	lockAllConfigurations()
}

dependencies {
	// BOM-y i podłogi CVE: platform-bom (gradle/bom).
	api(platform(libs.platform.bom))
	// Starter wnosi Spring MVC (api): kontrakt błędów dotyczy aplikacji z REST API.
	api("org.springframework.boot:spring-boot-starter-webmvc")
	// Walidacja i spring-dao są opcjonalne: handler rozpoznaje ich wyjątki po nazwie klasy, bez twardej zależności.
	compileOnly("jakarta.validation:jakarta.validation-api")
	compileOnly("org.springframework:spring-tx")
	annotationProcessor(platform(libs.platform.bom))
	annotationProcessor("org.springframework.boot:spring-boot-configuration-processor")

	testImplementation(platform(libs.platform.bom))
	testImplementation("org.springframework.boot:spring-boot-starter-test")
	testImplementation("org.springframework.boot:spring-boot-starter-validation")
	testImplementation("org.springframework:spring-tx")
	testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

// Złoty kontrakt contracts/problem-detail.json czyta ten test i test api-client (jedno źródło kształtu błędu).
val contracts = layout.projectDirectory.dir("../../contracts")
tasks.test {
	inputs.dir(contracts).withPropertyName("contracts").withPathSensitivity(PathSensitivity.RELATIVE)
	systemProperty("platform.contracts.dir", contracts.asFile.absolutePath)
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
