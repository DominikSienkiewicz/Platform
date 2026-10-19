package pl.seniordeveloper.gradle

import org.gradle.testkit.runner.GradleRunner
import java.io.File
import java.nio.file.Path

/**
 * Kopia startera z templates/jvm w katalogu testu, podpięta pod konwencje i katalog opublikowane
 * przez ten build do izolowanego repozytorium (platform.testRepository).
 */
internal class ConsumerFixture(
	private val directory: Path,
	template: String,
) {
	init {
		Path.of(System.getProperty("platform.templates"), template).toFile().copyRecursively(directory.toFile(), true)
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
				"-PplatformVersion=${System.getProperty("platform.version")}",
				"-PplatformRepository=${System.getProperty("platform.testRepository")}",
			)
		System.getProperty("platform.javaInstallations")?.takeIf { it.isNotBlank() }?.let {
			arguments += "-Porg.gradle.java.installations.paths=$it"
		}
		return arguments.toTypedArray()
	}
}
