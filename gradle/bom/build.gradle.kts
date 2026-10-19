// platform-bom (N-CAP-12, ADR-0013): kanał OGRANICZEŃ obok katalogu. Katalog trzyma aliasy i wersje, a BOM
// to, czego TOML nie wyrazi: importy BOM-ów, podłogi CVE i nadpisania zgodności z uzasadnieniem (because).
// Konsument: implementation(platform(libs.platform.bom)); test-fixtures i security-starter importują go zamiast
// osobnych BOM-ów. Każda wersja pochodzi z gradle/catalog; podłogę zdejmuje się razem z wpisem w katalogu.
plugins {
	`java-platform`
	`maven-publish`
}

group = "pl.seniordeveloper"
version = providers.gradleProperty("platformVersion").get()

javaPlatform {
	// Import innych platform (BOM-ów) to zależność, nie constraint.
	allowDependencies()
}

dependencies {
	// Jackson PRZED Bootem: przy imporcie POM-u przez io.spring.dependency-management wygrywa pierwszy
	// zaimportowany BOM, a w Gradle najwyższa wersja — ta kolejność daje poprawioną wersję w obu modelach.
	api(platform("tools.jackson:jackson-bom:${libs.versions.jacksonBom.get()}")) {
		because("CVE: Spring Boot ${libs.versions.springBoot.get()} manages Jackson 3.1.5 (High, fixed in 3.1.7)")
	}
	api(platform("com.fasterxml.jackson:jackson-bom:${libs.versions.jackson2Bom.get()}")) {
		because("CVE: Spring Boot ${libs.versions.springBoot.get()} manages Jackson 2.21.5 (High, fixed in 2.21.7)")
	}
	api(platform(libs.spring.boot.bom))
	api(platform(libs.spring.modulith.bom))
	api(platform(libs.spring.ai.bom))
	api(platform(libs.junit.bom))

	constraints {
		listOf("tomcat-embed-core", "tomcat-embed-el", "tomcat-embed-websocket").forEach { artifact ->
			api("org.apache.tomcat.embed:$artifact:${libs.versions.tomcat.get()}") {
				because("CVE: Spring Boot ${libs.versions.springBoot.get()} manages Tomcat 11.0.24 (three Critical, fixed in 11.0.25)")
			}
		}
		api("org.projectlombok:lombok:${libs.versions.lombok.get()}") {
			because("compatibility: Spring Boot ${libs.versions.springBoot.get()} manages Lombok 1.18.46, which fails on javac 27")
		}
		api("com.tngtech.archunit:archunit:${libs.versions.archunit.get()}") {
			because("compatibility: spring-modulith-core brings ArchUnit 1.4.2, which cannot read class-file 71 (Java 27)")
		}
		api(libs.archunit.junit5)
		api(libs.platform.test.fixtures)
		api(libs.platform.security.starter)
		api(libs.platform.observability.starter)
		api(libs.platform.web.starter)
	}
}

val gprOwner = providers.gradleProperty("gpr.owner").orElse(providers.environmentVariable("GPR_OWNER")).getOrElse("DominikSienkiewicz")
val gprRepo = providers.gradleProperty("gpr.repo").orElse(providers.environmentVariable("GPR_REPO")).getOrElse("Platform")

publishing {
	publications {
		create<MavenPublication>("maven") { from(components["javaPlatform"]) }
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

// Repozytorium testów TestKit w build-logic: spring-modulith-conventions importuje ten BOM, więc konsument
// w TestKit musi go rozwiązać tak samo jak katalog.
providers.gradleProperty("functionalTestRepository").orNull?.let { repository ->
	publishing.repositories.maven {
		name = "FunctionalTest"
		url = uri(repository)
	}
}
