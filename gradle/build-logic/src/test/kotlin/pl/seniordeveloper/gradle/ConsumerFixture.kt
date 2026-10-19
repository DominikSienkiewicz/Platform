package pl.seniordeveloper.gradle

import org.gradle.testkit.runner.GradleRunner
import java.io.File
import java.nio.file.Path

/**
 * Kopia startera z templates/jvm w katalogu testu, podpięta pod konwencje i katalog opublikowane
 * przez ten build do izolowanego repozytorium (platform.testRepository).
 *
 * Każdy przebieg idzie pod configuration cache i z `--warning-mode=all` (E1-15, Decyzja 10). `fail` byłoby właściwe,
 * ale gradle-pitest-plugin 1.19.0 woła przestarzałe Configuration.setVisible i nie ma wydania z poprawką; zamiast tego
 * [assertNoPlatformDeprecation] wywala test, gdy deprecacja pochodzi z konwencji Platform. Wróć do `fail`, gdy plugin
 * PIT przestanie ją zgłaszać. Toolchain przez `-D`, bo konfigurowanie toolchainów przez `-P` znika w Gradle 10.
 */
internal class ConsumerFixture private constructor(
	private val directory: Path,
) {
	constructor(directory: Path, template: String) : this(directory) {
		Path.of(System.getProperty("platform.templates"), template).toFile().copyRecursively(directory.toFile(), true)
	}

	companion object {
		/** Konsument, który już leży w katalogu, np. wyrenderowany przez scripts/new-consumer.sh. */
		fun existing(directory: Path): ConsumerFixture = ConsumerFixture(directory)
	}

	fun file(relativePath: String): File = directory.resolve(relativePath).toFile()

	fun appendToBuildScript(text: String) {
		file("build.gradle.kts").appendText("\n$text\n")
	}

	fun runner(
		vararg tasks: String,
		properties: Map<String, String> = emptyMap(),
	): GradleRunner =
		GradleRunner
			.create()
			.withProjectDir(directory.toFile())
			.forwardOutput()
			.withArguments(*arguments(), *properties.map { (name, value) -> "-P$name=$value" }.toTypedArray(), *tasks)

	private fun arguments(): Array<String> {
		val arguments =
			mutableListOf(
				"--stacktrace",
				"--max-workers=2",
				"--no-parallel",
				"--configuration-cache",
				"--warning-mode=all",
				// Kanał deprecacji w trybie strict (N-REL-9): starter użyty przez Platform nie może być przestarzały.
				"-Pplatform.deprecations=fail",
				"-PplatformVersion=${System.getProperty("platform.version")}",
				"-PplatformRepository=${System.getProperty("platform.testRepository")}",
			)
		System.getProperty("platform.javaInstallations")?.takeIf { it.isNotBlank() }?.let {
			arguments += "-Dorg.gradle.java.installations.paths=$it"
		}
		return arguments.toTypedArray()
	}
}

/**
 * Deprecacja Gradle'a z kodu Platform: pierwsza ramka stosu (`--stacktrace`) spoza Gradle'a i JDK, czyli kod, który
 * wywołał przestarzałe API, to skrypt convention pluginu (`Seniordev_…`) albo klasa pl.seniordeveloper.gradle.
 * Deprecacje zewnętrznych pluginów (np. PIT aplikowany z quality-conventions) zostają w logu, ale nie wywalają testu.
 */
internal fun assertNoPlatformDeprecation(output: String) {
	val warnings =
		Regex("""(?m)^.*(?:has been deprecated|is deprecated).*(?:\n\s+at .*)*""")
			.findAll(output)
			.map { it.value }
			.filter { warning ->
				val caller =
					warning
						.lineSequence()
						.map { it.trim() }
						.filter { it.startsWith("at ") }
						.map { it.removePrefix("at ") }
						.firstOrNull { frame ->
							listOf("org.gradle.", "java.", "jdk.", "sun.", "kotlin.", "groovy.", "org.codehaus.groovy.").none { frame.startsWith(it) }
						}
				caller != null && (caller.startsWith("Seniordev_") || caller.startsWith("pl.seniordeveloper.gradle."))
			}.toList()
	org.junit.jupiter.api.Assertions.assertTrue(
		warnings.isEmpty(),
		"Platform conventions use deprecated Gradle API:\n" + warnings.joinToString("\n\n"),
	)
}
