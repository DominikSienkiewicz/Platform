package pl.seniordeveloper.gradle

import org.gradle.testkit.runner.GradleRunner
import org.gradle.testkit.runner.TaskOutcome
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.nio.file.Path

class PlatformConsumerFunctionalTest {
	@TempDir
	lateinit var directory: Path

	@Test
	fun `published conventions compile and test a pure Java consumer`() {
		val result = consumer("java-library").withArguments(
			*arguments(), "test", "spotlessCheck", "checkstyleMain", "checkstyleTest", "platformDependencyCheck",
		).build()
		assertEquals(TaskOutcome.SUCCESS, result.task(":test")?.outcome)
		assertEquals(TaskOutcome.SUCCESS, result.task(":platformDependencyCheck")?.outcome)
	}

	@Test
	fun `published conventions package and start a Spring consumer`() {
		val result = consumer("spring-app").withArguments(
			*arguments(), "bootJar", "integrationTest", "spotlessCheck", "checkstyleMain", "checkstyleTest", "platformDependencyCheck",
		).build()
		assertEquals(TaskOutcome.SUCCESS, result.task(":bootJar")?.outcome)
		assertEquals(TaskOutcome.SUCCESS, result.task(":integrationTest")?.outcome)
	}

	@Test
	fun `agent profile bounds test resources and leaves human settings alone`() {
		val runner = consumer("java-library")
		directory.resolve("build.gradle.kts").toFile().appendText(
			"""

			tasks.register("inspectBudget") {
			    val test = tasks.named<Test>("test").get()
			    val forks = test.maxParallelForks
			    val heap = test.maxHeapSize
			    val contexts = test.systemProperties["spring.test.context.cache.maxSize"]
			    doLast { println("BUDGET:${'$'}forks:${'$'}heap:${'$'}contexts") }
			}
			""".trimIndent(),
		)
		val environment = System.getenv().toMutableMap()
		environment.remove("AI_AGENT")
		val human = runner.withEnvironment(environment).withArguments(*arguments(), "inspectBudget").build()
		assertTrue(human.output.lineSequence().single { it.startsWith("BUDGET:") }.endsWith(":null"))
		environment["AI_AGENT"] = "1"
		val agent = runner.withEnvironment(environment).withArguments(*arguments(), "inspectBudget").build()
		assertTrue(agent.output.contains("BUDGET:1:2g:4"))
	}

	private fun consumer(name: String): GradleRunner {
		Path.of(System.getProperty("platform.templates"), name).toFile().copyRecursively(directory.toFile(), true)
		return GradleRunner.create().withProjectDir(directory.toFile()).forwardOutput()
	}

	private fun arguments(): Array<String> {
		val arguments = mutableListOf(
			"--stacktrace", "--max-workers=2", "--no-parallel",
			"-PplatformVersion=${System.getProperty("platform.version")}",
			"-PplatformRepository=${System.getProperty("platform.testRepository")}",
		)
		System.getProperty("platform.javaInstallations")?.takeIf { it.isNotBlank() }?.let {
			arguments += "-Porg.gradle.java.installations.paths=$it"
		}
		return arguments.toTypedArray()
	}
}
