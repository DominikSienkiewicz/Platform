package pl.seniordeveloper.gradle

import org.gradle.testkit.runner.GradleRunner
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.nio.file.Path

/** N-DX-2: pierwszy build bez poświadczeń GitHub Packages nazywa naprawę, zamiast „plugin not found”. */
class PlatformCredentialPreflightFunctionalTest {
	@TempDir
	lateinit var directory: Path

	private val withoutCredentials =
		System.getenv().toMutableMap().apply {
			remove("GITHUB_ACTOR")
			remove("GITHUB_TOKEN")
		}

	@Test
	fun `a build without credentials or a local Platform names the fix`() {
		ConsumerFixture(directory, "java-library")

		val result = runner("help").buildAndFail()
		assertTrue(result.output.contains("No GitHub Packages credentials, so the Platform plugins cannot resolve."))
		assertTrue(
			result.output.contains("gpr.user and gpr.key") && result.output.contains("read:packages"),
			"the message must name both options",
		)
	}

	@Test
	fun `an offline build is left to Gradle`() {
		ConsumerFixture(directory, "java-library")

		val result = runner("help", "--offline").buildAndFail()
		assertFalse(result.output.contains("No GitHub Packages credentials"), "--offline needs no credentials")
	}

	private fun runner(vararg arguments: String): GradleRunner =
		GradleRunner
			.create()
			.withProjectDir(directory.toFile())
			.withEnvironment(withoutCredentials)
			.withArguments(*arguments, "-PplatformVersion=${System.getProperty("platform.version")}")
}
