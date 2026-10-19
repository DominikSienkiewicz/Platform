package pl.seniordeveloper.gradle

import org.gradle.testkit.runner.TaskOutcome
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.nio.file.Path

/**
 * Konsumenci jadą na własnym wrapperze, często starszym niż ten, którym Platform kompiluje pluginy
 * (kotlin-dsl). Ten test buduje startera na najstarszym obiecanym Gradle (minimumConsumerGradle), więc
 * kombinacja, której dotąd nikt nie uruchamiał, jest sprawdzana przed wydaniem, a nie przy bumpie konsumenta.
 */
class PlatformMinimumGradleFunctionalTest {
	@TempDir
	lateinit var directory: Path

	@Test
	fun `published conventions build a consumer on the minimum supported Gradle`() {
		val minimum = System.getProperty("platform.minimumConsumerGradle")
		val result = ConsumerFixture(directory, "java-library").runner("build").withGradleVersion(minimum).build()

		assertEquals(TaskOutcome.SUCCESS, result.task(":build")?.outcome, "the consumer build must pass on Gradle $minimum")
	}
}
