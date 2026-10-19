package pl.seniordeveloper.gradle

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.nio.file.Path

/** Profil agenta jako kontrakt (N-SHOW-2) i nadpisanie toolchainu dla kanarka (N-REL-4). */
class PlatformAgentProfileFunctionalTest {
	@TempDir
	lateinit var directory: Path

	@Test
	fun `explicit agent knobs win and the banner appears once per build`() {
		val consumer = twoProjectConsumer()
		val knobs = mapOf("springContextCacheSize" to "8", "platformAgentTestHeap" to "3g")

		val agent = consumer.runner("inspectBudget", properties = knobs).withEnvironment(environment(agent = true)).build()
		assertEquals("BUDGET:1:3g:8", budget(agent.output))
		assertEquals(
			1,
			agent.output.lineSequence().count { it.startsWith("Platform agent profile: testForks=1 testHeap=3g springContextCache=8") },
			"one banner per build, not per project",
		)

		val human = consumer.runner("inspectBudget", properties = knobs).withEnvironment(environment(agent = false)).build()
		assertEquals("BUDGET:1:3g:8", budget(human.output), "an explicit property applies in every mode")
		assertFalse(human.output.contains("Platform agent profile:"), "the banner belongs to agent mode")
	}

	@Test
	fun `toolchain override replaces the canon toolchain and says so`() {
		val consumer = ConsumerFixture(directory, "java-library")
		consumer.appendToBuildScript(
			"""
			tasks.register("inspectToolchain") {
			    val version = java.toolchain.languageVersion.map { it.asInt() }
			    doLast { println("TOOLCHAIN:${'$'}{version.get()}") }
			}
			""".trimIndent(),
		)
		val canon = consumer.runner("inspectToolchain").build()
		assertEquals("TOOLCHAIN:${PlatformVersions.JAVA}", line(canon.output, "TOOLCHAIN:"))

		val override = consumer.runner("inspectToolchain", properties = mapOf("platformToolchainOverride" to "28")).build()
		assertEquals("TOOLCHAIN:28", line(override.output, "TOOLCHAIN:"))
		assertTrue(override.output.contains("platformToolchainOverride=28 replaces the Java"), "the override must be visible")
	}

	private fun twoProjectConsumer(): ConsumerFixture {
		val consumer = ConsumerFixture(directory, "java-library")
		consumer.file("settings.gradle.kts").appendText("\ninclude(\"sub\")\n")
		consumer.file("sub").mkdirs()
		consumer.file("sub/build.gradle.kts").writeText("plugins {\n\tjava\n\tid(\"seniordev.java-conventions\")\n}\n")
		consumer.appendToBuildScript(
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
		return consumer
	}

	private fun budget(output: String): String = line(output, "BUDGET:")

	private fun line(
		output: String,
		prefix: String,
	): String = output.lineSequence().single { it.startsWith(prefix) }

	private fun environment(agent: Boolean): Map<String, String> =
		System.getenv().toMutableMap().apply {
			if (agent) put("AI_AGENT", "1") else remove("AI_AGENT")
		}
}
