plugins {
	`kotlin-dsl`
	`maven-publish`
}

group = "pl.seniordeveloper.gradle"
version = providers.gradleProperty("platformVersion").getOrElse("1.0.0")

// Pin toolchainu na 25, żeby compileJava i compileKotlin celowały w ten sam JVM-target niezależnie
// od ambientowego JDK (lokalnie JDK 26 dawał ostrzeżenie o niespójności 26 vs 25).
java {
	toolchain {
		languageVersion = JavaLanguageVersion.of(25)
	}
}

repositories {
	gradlePluginPortal()
	mavenCentral()
}

// Dependency locking — powtarzalne rozwiązywanie zależności (gradle.lockfile).
// Regeneracja po bumpie którejkolwiek wersji wyżej: ./gradlew dependencies --write-locks
dependencyLocking {
	lockAllConfigurations()
}

dependencies {
	// Pluginy aplikowane WEWNĄTRZ convention pluginów muszą być na classpath build-logic
	// jako zwykłe zależności (marker-artefakty pluginów). Wersje pochodzą z kanonu
	// (gradle/catalog/libs.versions.toml) dołączonego w settings.gradle.kts.
	implementation("io.spring.gradle:dependency-management-plugin:${libs.versions.springDependencyManagement.get()}")
	implementation("com.diffplug.spotless:spotless-plugin-gradle:${libs.versions.spotless.get()}")
	implementation("com.github.spotbugs.snom:spotbugs-gradle-plugin:${libs.versions.spotbugsPlugin.get()}")
	implementation("info.solidsoft.gradle.pitest:gradle-pitest-plugin:${libs.versions.pitest.get()}")
	implementation("org.cyclonedx:cyclonedx-gradle-plugin:${libs.versions.cyclonedx.get()}")
	implementation("org.sonarqube:org.sonarqube.gradle.plugin:${libs.versions.sonarqube.get()}")
	// Settings plugin (toolchain auto-provisioning) — aplikowany przez seniordev.settings-conventions.
	implementation("org.gradle.toolchains:foojay-resolver:${libs.versions.foojayResolver.get()}")

	// Testy configów platformy (guard checkstyle ↔ google-java-format).
	// Checkstyle = lustro toolVersion w seniordev.java-conventions (te same reguły co u konsumenta);
	// precompiled script plugin nie czyta katalogu w czasie kompilacji, więc lustro zostaje TAM,
	// a tu bierzemy tę samą wartość z kanonu.
	testImplementation("com.puppycrawl.tools:checkstyle:${libs.versions.checkstyle.get()}")
	testImplementation(platform("org.junit:junit-bom:${libs.versions.junit.get()}"))
	testImplementation("org.junit.jupiter:junit-jupiter")
	testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

tasks.withType<Test>().configureEach {
	useJUnitPlatform()
	// Guard luster wersji: test porównuje wersje wpisane w źródłach convention pluginów z kanonem.
	val javaConventions = layout.projectDirectory.file("src/main/kotlin/seniordev.java-conventions.gradle.kts")
	val springModulithConventions =
		layout.projectDirectory.file("src/main/kotlin/seniordev.spring-modulith-conventions.gradle.kts")
	val qualityConventions = layout.projectDirectory.file("src/main/kotlin/seniordev.quality-conventions.gradle.kts")
	inputs.file(javaConventions)
	inputs.file(springModulithConventions)
	inputs.file(qualityConventions)
	val workflows = layout.projectDirectory.dir("../../.github/workflows")
	inputs.dir(workflows)
	inputs.property("canonGoogleJavaFormat", libs.versions.googleJavaFormat.get())
	inputs.property("canonJava", libs.versions.java.get())
	inputs.property("canonLombok", libs.versions.lombok.get())
	inputs.property("canonPitestTool", libs.versions.pitestTool.get())
	systemProperty("platform.javaConventions", javaConventions.asFile.absolutePath)
	systemProperty("platform.springModulithConventions", springModulithConventions.asFile.absolutePath)
	systemProperty("platform.canon.googleJavaFormat", libs.versions.googleJavaFormat.get())
	systemProperty("platform.canon.java", libs.versions.java.get())
	systemProperty("platform.canon.lombok", libs.versions.lombok.get())
	systemProperty("platform.qualityConventions", qualityConventions.asFile.absolutePath)
	systemProperty("platform.canon.pitestTool", libs.versions.pitestTool.get())
	systemProperty("platform.workflows", workflows.asFile.absolutePath)
}

// --- Publikacja do GitHub Packages (Maven) ---
val gprOwner = providers.gradleProperty("gpr.owner").orElse(providers.environmentVariable("GPR_OWNER")).getOrElse("DominikSienkiewicz")
val gprRepo = providers.gradleProperty("gpr.repo").orElse(providers.environmentVariable("GPR_REPO")).getOrElse("Platform")

publishing {
	publications {
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
