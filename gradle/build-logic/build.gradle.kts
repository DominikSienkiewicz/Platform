plugins {
	`kotlin-dsl`
	`maven-publish`
	alias(libs.plugins.spotless)
}

group = "pl.seniordeveloper.gradle"
version = providers.gradleProperty("platformVersion").get()

// Pin toolchainu na 25, żeby compileJava i compileKotlin celowały w ten sam JVM-target niezależnie
// od ambientowego JDK (lokalnie JDK 26 dawał ostrzeżenie o niespójności 26 vs 25).
java {
	toolchain {
		languageVersion = JavaLanguageVersion.of(25)
	}
	// Źródła convention pluginów obok binarki: konsument czyta w IDE, co plugin robi z jego buildem.
	withSourcesJar()
}

repositories {
	gradlePluginPortal()
	mavenCentral()
}

// Źródła convention pluginów formatuje ktlint, jak konsumentów google-java-format: kod o największym zasięgu
// nie może mieć słabszej higieny niż ten, który sprawdza. Taby i reszta stylu z .editorconfig roota repo.
val repositoryEditorConfig = layout.projectDirectory.file("../../.editorconfig")
spotless {
	kotlin {
		target("src/**/*.kt")
		ktlint(libs.versions.ktlint.get()).setEditorConfigPath(repositoryEditorConfig)
	}
	kotlinGradle {
		target("*.gradle.kts", "src/**/*.gradle.kts")
		ktlint(libs.versions.ktlint.get()).setEditorConfigPath(repositoryEditorConfig)
	}
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
	testImplementation(gradleTestKit())
	testImplementation("com.puppycrawl.tools:checkstyle:${libs.versions.checkstyle.get()}")
	// google-java-format z kanonu (lustro googleJavaFormat(...) w java-conventions): PlatformFormatterCheckstyleTest
	// formatuje korpus tym samym formaterem, którego używa Spotless konsumenta, i sprawdza wynik Checkstyle.
	testImplementation("com.google.googlejavaformat:google-java-format:${libs.versions.googleJavaFormat.get()}")
	testImplementation(platform("org.junit:junit-bom:${libs.versions.junit.get()}"))
	testImplementation("org.junit.jupiter:junit-jupiter")
	testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

tasks.withType<Test>().configureEach {
	useJUnitPlatform()
	// google-java-format używa wewnętrznego API javac; Spotless otwiera te pakiety tak samo.
	jvmArgs(
		listOf("api", "code", "file", "parser", "tree", "util").map { "--add-exports=jdk.compiler/com.sun.tools.javac.$it=ALL-UNNAMED" },
	)
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
	// PlatformReferenceDocTest: każde pokrętło czytane w src/main/kotlin musi stać w docs/reference.md.
	val conventionSources = layout.projectDirectory.dir("src/main/kotlin")
	val referenceDoc = layout.projectDirectory.file("../../docs/reference.md")
	inputs.dir(conventionSources)
	inputs.file(referenceDoc)
	// CompatibilityMatrixTest: górny wiersz docs/compatibility.md kontra katalog, Dockerfile i frontend.
	val compatibilityDoc = layout.projectDirectory.file("../../docs/compatibility.md")
	val dockerfileTemplate = layout.projectDirectory.file("../../templates/Dockerfile.backend")
	val frontendManifest = layout.projectDirectory.file("../../frontend/package.json")
	val frontendCanon = layout.projectDirectory.file("../../frontend/packages/versions/versions.json")
	inputs.files(compatibilityDoc, dockerfileTemplate, frontendManifest, frontendCanon)
	// Kanon każdego lustra z tabeli w docs/versions.md (PlatformToolVersionMirrorTest + PlatformCatalogMirrorTest).
	mapOf(
		"googleJavaFormat" to libs.versions.googleJavaFormat,
		"java" to libs.versions.java,
		"archunit" to libs.versions.archunit,
		"lombok" to libs.versions.lombok,
		"gradle" to libs.versions.gradle,
		"tomcat" to libs.versions.tomcat,
		"jacksonBom" to libs.versions.jacksonBom,
		"jackson2Bom" to libs.versions.jackson2Bom,
		"pitestTool" to libs.versions.pitestTool,
		"pitestJunit5" to libs.versions.pitestJunit5,
		"checkstyle" to libs.versions.checkstyle,
		"jacoco" to libs.versions.jacoco,
		"spotbugs" to libs.versions.spotbugs,
		"springBoot" to libs.versions.springBoot,
		"springModulith" to libs.versions.springModulith,
		"springAi" to libs.versions.springAi,
		"junit" to libs.versions.junit,
		"jsoup" to libs.versions.jsoup,
	).forEach { (name, version) ->
		inputs.property("canon.$name", version)
		systemProperty("platform.canon.$name", version.get())
	}
	systemProperty("platform.javaConventions", javaConventions.asFile.absolutePath)
	systemProperty("platform.springModulithConventions", springModulithConventions.asFile.absolutePath)
	systemProperty("platform.qualityConventions", qualityConventions.asFile.absolutePath)
	systemProperty("platform.workflows", workflows.asFile.absolutePath)
	// PlatformGradleVersionMirrorTest: wrappery wszystkich modułów i literał minimum w settings-conventions.
	val gradleModules = layout.projectDirectory.dir("..")
	val settingsConventions = layout.projectDirectory.file("src/main/kotlin/seniordev.settings-conventions.settings.gradle.kts")
	inputs.file(settingsConventions)
	inputs.property("minimumConsumerGradle", providers.gradleProperty("minimumConsumerGradle"))
	systemProperty("platform.gradleModules", gradleModules.asFile.absolutePath)
	systemProperty("platform.settingsConventions", settingsConventions.asFile.absolutePath)
	systemProperty("platform.minimumConsumerGradle", providers.gradleProperty("minimumConsumerGradle").get())
	systemProperty("platform.conventionSources", conventionSources.asFile.absolutePath)
	systemProperty("platform.referenceDoc", referenceDoc.asFile.absolutePath)
	systemProperty("platform.compatibilityDoc", compatibilityDoc.asFile.absolutePath)
	systemProperty("platform.dockerfileTemplate", dockerfileTemplate.asFile.absolutePath)
	systemProperty("platform.frontendManifest", frontendManifest.asFile.absolutePath)
	systemProperty("platform.frontendCanon", frontendCanon.asFile.absolutePath)
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

// Repozytorium Maven bez poświadczeń dołączane do GitHub Release (scripts/release-assets.sh, N-SHOW-9).
providers.gradleProperty("platformBundleRepository").orNull?.let { repository ->
	publishing.repositories.maven {
		name = "Bundle"
		url = uri(repository)
	}
}

val functionalTestRepository = layout.buildDirectory.dir("functional-test-repository")
publishing.repositories.maven {
	name = "FunctionalTest"
	url = uri(functionalTestRepository)
}

val publishFunctionalTestCatalog =
	tasks.register<GradleBuild>("publishFunctionalTestCatalog") {
		dir = file("../catalog")
		tasks = listOf("publishAllPublicationsToFunctionalTestRepository")
		startParameter.projectProperties =
			mapOf(
				"platformVersion" to project.version.toString(),
				"functionalTestRepository" to functionalTestRepository.get().asFile.absolutePath,
			)
	}

tasks.named<Test>("test") {
	dependsOn("publishAllPublicationsToFunctionalTestRepository", publishFunctionalTestCatalog)
	val templates = layout.projectDirectory.dir("../../templates/jvm")
	inputs.dir(templates)
	inputs.file(layout.projectDirectory.file("../catalog/libs.versions.toml"))
	inputs.file(layout.projectDirectory.file("../catalog/build.gradle.kts"))
	systemProperty("platform.templates", templates.asFile.absolutePath)
	systemProperty(
		"platform.testRepository",
		functionalTestRepository
			.get()
			.asFile
			.toURI()
			.toString(),
	)
	systemProperty("platform.version", project.version.toString())
	systemProperty("platform.javaInstallations", providers.gradleProperty("org.gradle.java.installations.paths").getOrElse(""))
}
