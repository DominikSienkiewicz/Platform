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
	// Wariant `tracing`: OpenTelemetry (ślady + eksport OTLP) tylko u konsumenta, który go zażąda capability
	// pl.seniordeveloper:platform-observability-starter-tracing; bez tego starter nie wnosi exportera.
	registerFeature("tracing") { usingSourceSet(sourceSets["main"]) }
}

repositories { mavenCentral() }

// Decyzja 28: jak pozostałe moduły Java Platform — SonarQube Cloud z quality-conventions.
pitest {
	targetClasses.set(listOf("pl.seniordeveloper.platform.observability.*"))
}

// Dependency locking — powtarzalne rozwiązywanie zależności (gradle.lockfile).
dependencyLocking {
	lockAllConfigurations()
}

dependencies {
	// BOM-y i podłogi CVE: platform-bom (gradle/bom).
	api(platform(libs.platform.bom))
	// Starter wnosi actuator (api); rejestr Prometheusa tylko w runtime — endpoint wystawia się opt-in.
	api("org.springframework.boot:spring-boot-starter-actuator")
	runtimeOnly("io.micrometer:micrometer-registry-prometheus")
	"tracingApi"(platform(libs.platform.bom))
	"tracingApi"("org.springframework.boot:spring-boot-starter-opentelemetry")
	// Konfiguracja annotationProcessor nie dziedziczy BOM-a z api — platforma osobno.
	annotationProcessor(platform(libs.platform.bom))
	annotationProcessor("org.springframework.boot:spring-boot-configuration-processor")

	testImplementation(platform(libs.platform.bom))
	testImplementation("org.springframework.boot:spring-boot-starter-test")
	testImplementation("org.springframework.boot:spring-boot-starter-webmvc")
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
