plugins {
	`version-catalog`
	`maven-publish`
}

group = "pl.seniordeveloper"
version = providers.gradleProperty("platformVersion").getOrElse("1.3.8")

catalog {
	versionCatalog {
		// ============================ WERSJE ============================
		version("platform", providers.gradleProperty("platformVersion").getOrElse("1.3.8"))
		version("java", "25")
		version("springBoot", "4.0.6")
		version("springDependencyManagement", "1.1.7")
		version("springModulith", "2.0.6")
		version("springAi", "2.0.0-M8")       // GA jeszcze nie wyszło; stabilna 1.1.7 nie wspiera Boot 4, więc zostajemy na sprawdzonym M8 (komplet w verification-metadata). NIE bumpować na RC/M bez `--write-verification-metadata`. Bump na 2.0.0 gdy GA.
		version("junit", "6.1.0")
		version("archunit", "1.4.2")
		version("resilience4j", "2.4.0")
		version("bucket4j", "8.19.0")
		version("shedlock", "7.7.0")
		version("javers", "7.11.1")
		version("spotless", "8.6.0")
		version("pitest", "1.19.0")
		version("pitestJunit5", "1.2.3")
		version("cyclonedx", "3.2.4")
		version("jacoco", "0.8.15")
		version("foojayResolver", "1.0.0") // lustro: implementation foojay-resolver w build-logic

		// ============================ BOM-y ============================
		library("spring-ai-bom", "org.springframework.ai", "spring-ai-bom").versionRef("springAi")
		library("spring-modulith-bom", "org.springframework.modulith", "spring-modulith-bom").versionRef("springModulith")
		library("junit-bom", "org.junit", "junit-bom").versionRef("junit")

		// ===================== BIBLIOTEKI (jawna wersja) =====================
		// FIX: poprawny wariant pod Spring Boot 4 (SkillSprintPlus miał resilience4j-spring-boot3).
		library("resilience4j-spring-boot4", "io.github.resilience4j", "resilience4j-spring-boot4").versionRef("resilience4j")
		library("bucket4j-core", "com.bucket4j", "bucket4j_jdk17-core").versionRef("bucket4j")
		library("shedlock-spring", "net.javacrumbs.shedlock", "shedlock-spring").versionRef("shedlock")
		library("shedlock-provider-jdbc-template", "net.javacrumbs.shedlock", "shedlock-provider-jdbc-template").versionRef("shedlock")
		library("javers-spring-boot-starter-sql", "org.javers", "javers-spring-boot-starter-sql").versionRef("javers")
		library("archunit-junit5", "com.tngtech.archunit", "archunit-junit5").versionRef("archunit")
		// Reużywalna infrastruktura testowa (Testcontainers + bazy testów) — z gradle/test-fixtures.
		library("platform-test-fixtures", "pl.seniordeveloper", "platform-test-fixtures").versionRef("platform")

		// ============================ PLUGINY ============================
		plugin("spring-boot", "org.springframework.boot").versionRef("springBoot")
		plugin("spring-dependency-management", "io.spring.dependency-management").versionRef("springDependencyManagement")
		plugin("spotless", "com.diffplug.spotless").versionRef("spotless")
		plugin("pitest", "info.solidsoft.pitest").versionRef("pitest")
		plugin("cyclonedx", "org.cyclonedx.bom").versionRef("cyclonedx")

		// Convention pluginy publikowane z gradle/build-logic (id = nazwa pliku *.gradle.kts).
		plugin("conventions-java", "seniordev.java-conventions").versionRef("platform")
		plugin("conventions-quality", "seniordev.quality-conventions").versionRef("platform")
		plugin("conventions-spring-modulith", "seniordev.spring-modulith-conventions").versionRef("platform")
		// Settings plugin (foojay + repozytoria) — aplikowany w settings.gradle.kts konsumenta,
		// więc i tak pinowany tam jawnie (settings plugins{} nie czyta katalogu); wpis dla kompletu.
		plugin("conventions-settings", "seniordev.settings-conventions").versionRef("platform")
	}
}

val gprOwner = providers.gradleProperty("gpr.owner").orElse(providers.environmentVariable("GPR_OWNER")).getOrElse("DominikSienkiewicz")
val gprRepo = providers.gradleProperty("gpr.repo").orElse(providers.environmentVariable("GPR_REPO")).getOrElse("Platform")

publishing {
	publications {
		create<MavenPublication>("maven") {
			from(components["versionCatalog"])
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
