package pl.seniordeveloper.gradle

import org.gradle.testkit.runner.GradleRunner
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.ValueSource
import java.nio.file.Path

/**
 * N-DX-18: pusta albo z samych spacji wartość poświadczeń liczy się jak brak. Devcontainer konsumenta przekazuje
 * nieustawioną zmienną hosta jako "", a puste `gpr.*` w gradle.properties to ten sam przypadek. `orElse` przechodzi
 * dalej tylko przy braku wartości, więc bez filtra pusta wartość omija preflight (żądanie z pustym tokenem kończy się
 * 401 schowanym pod „plugin not found”) i zasłania niepustą zmienną środowiska.
 */
class PlatformBlankCredentialPreflightFunctionalTest {
	@TempDir
	lateinit var directory: Path

	@ParameterizedTest
	@ValueSource(strings = ["java-library", "spring-app"])
	fun `empty GITHUB_ACTOR and GITHUB_TOKEN count as missing`(template: String) {
		ConsumerFixture(directory, template)

		assertNamesTheCredentialFix(preflightRunner(environment(actor = "", token = "")).buildAndFail().output)
	}

	@Test
	fun `whitespace-only GITHUB_ACTOR and GITHUB_TOKEN count as missing`() {
		ConsumerFixture(directory, "java-library")

		assertNamesTheCredentialFix(preflightRunner(environment(actor = "  ", token = " \t ")).buildAndFail().output)
	}

	@Test
	fun `empty gpr user and key in gradle properties count as missing`() {
		ConsumerFixture(directory, "java-library").file("gradle.properties").appendText("\ngpr.user=\ngpr.key=\n")

		assertNamesTheCredentialFix(preflightRunner(environment(actor = null, token = null)).buildAndFail().output)
	}

	@Test
	fun `empty gpr user and key fall back to the environment in the repository of the settings plugin`() {
		val consumer = ConsumerFixture(directory, "java-library")
		consumer.file("gradle.properties").appendText("\ngpr.user=\ngpr.key=\n")
		consumer.file("settings.gradle.kts").appendText(
			"""

			(dependencyResolutionManagement.repositories.getByName("GitHubPackages")
				as org.gradle.api.artifacts.repositories.MavenArtifactRepository).credentials.let {
				println("GITHUB_PACKAGES_CREDENTIALS:${'$'}{it.username}:${'$'}{it.password}")
			}
			""".trimIndent(),
		)

		// Fixture przekazuje -PplatformRepository, więc preflight startera nie wchodzi w drogę.
		val result = consumer.runner("help").withEnvironment(environment(actor = "dummy-actor", token = "dummy-token")).build()
		assertTrue(
			result.output.contains("GITHUB_PACKAGES_CREDENTIALS:dummy-actor:dummy-token"),
			"an empty gpr.user/gpr.key must not hide GITHUB_ACTOR/GITHUB_TOKEN:\n${result.output}",
		)
	}

	private fun assertNamesTheCredentialFix(output: String) {
		assertTrue(
			output.contains("No GitHub Packages credentials, so the Platform plugins cannot resolve."),
			"a blank credential must stop the build with the credentials message, not reach GitHub Packages:\n$output",
		)
	}

	/** Środowisko testu z podanymi GITHUB_ACTOR/GITHUB_TOKEN; `null` usuwa zmienną. */
	private fun environment(
		actor: String?,
		token: String?,
	): Map<String, String> =
		System.getenv().toMutableMap().apply {
			remove("GITHUB_ACTOR")
			remove("GITHUB_TOKEN")
			actor?.let { put("GITHUB_ACTOR", it) }
			token?.let { put("GITHUB_TOKEN", it) }
		}

	/** Jak w PlatformCredentialPreflightFunctionalTest: bez -PplatformRepository, żeby preflight w ogóle działał. */
	private fun preflightRunner(environment: Map<String, String>): GradleRunner =
		GradleRunner
			.create()
			.withProjectDir(directory.toFile())
			.withEnvironment(environment)
			.withArguments("help", "-PplatformVersion=${System.getProperty("platform.version")}")
}
