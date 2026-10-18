package pl.seniordeveloper.gradle

import java.io.File
import java.nio.file.Path
import javax.xml.parsers.DocumentBuilderFactory
import org.gradle.testkit.runner.BuildResult
import org.gradle.testkit.runner.TaskOutcome
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import org.w3c.dom.Element

class PlatformConsumerFunctionalTest {
	@TempDir
	lateinit var directory: Path

	@Test
	fun `published conventions run the consumer CI build on a pure Java consumer`() {
		val result = ConsumerFixture(directory, "java-library").runner("build", "cyclonedxBom", "pitest").build()

		assertSucceeded(result, ":test", ":pitest", *CONSUMER_GATES)
		assertAnalyzersReadTheBytecode(result)
	}

	@Test
	fun `published conventions build, package and start a Spring consumer`() {
		val consumer = ConsumerFixture(directory, "spring-app")
		val buildScript = consumer.file("build.gradle.kts")
		buildScript.writeText("import java.time.Duration\n\n" + buildScript.readText())
		consumer.appendToBuildScript(SMOKE_START_BOOT_JAR)

		val result = consumer.runner("build", "cyclonedxBom", "smokeStartBootJar").build()

		assertSucceeded(result, ":test", ":integrationTest", ":bootJar", ":smokeStartBootJar", *CONSUMER_GATES)
		assertAnalyzersReadTheBytecode(result)
		assertTrue(consumer.file("build/jacoco/integrationTest.exec").isFile, "integrationTest must record JaCoCo execution data")
		assertTrue(
			coveredInstructions(consumer.file("build/reports/jacoco/test/jacocoTestReport.xml"), "example/app/Application") > 0,
			"jacocoTestReport.xml (the report Sonar reads) must include integrationTest coverage: only the integration-tagged test starts Application",
		)
		val sbom = sbom(consumer)
		assertTrue(sbom.contains("spring-boot-starter-webmvc"), "the SBOM must list the runtime classpath")
		listOf("com.puppycrawl.tools", "plexus-utils", "checkstyle").forEach { tooling ->
			assertFalse(sbom.contains(tooling), "the SBOM must cover runtimeClasspath only, but it lists $tooling")
		}
	}

	@Test
	fun `agent profile bounds test resources and leaves human settings alone`() {
		val consumer = ConsumerFixture(directory, "java-library")
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
		val environment = System.getenv().toMutableMap()
		environment.remove("AI_AGENT")
		val human = consumer.runner("inspectBudget").withEnvironment(environment).build()
		assertTrue(human.output.lineSequence().single { it.startsWith("BUDGET:") }.endsWith(":null"))
		environment["AI_AGENT"] = "1"
		val agent = consumer.runner("inspectBudget").withEnvironment(environment).build()
		assertTrue(agent.output.contains("BUDGET:1:2g:4"))
	}

	@Test
	fun `published catalog carries the injected platform version, not its placeholder`() {
		val consumer = ConsumerFixture(directory, "java-library")
		consumer.appendToBuildScript(
			"""
			tasks.register("inspectCatalog") {
			    val platform = libs.versions.platform.get()
			    doLast { println("CATALOG_PLATFORM:${'$'}platform") }
			}
			""".trimIndent(),
		)
		val result = consumer.runner("inspectCatalog").build()
		assertEquals(
			"CATALOG_PLATFORM:${System.getProperty("platform.version")}",
			result.output.lineSequence().single { it.startsWith("CATALOG_PLATFORM:") },
		)
	}

	private fun assertSucceeded(result: BuildResult, vararg taskPaths: String) {
		taskPaths.forEach { path ->
			val outcome = result.task(path)?.outcome
			assertTrue(outcome != null && outcome in EXECUTED, "$path must run in the consumer build, but its outcome was $outcome")
		}
	}

	private fun assertAnalyzersReadTheBytecode(result: BuildResult) {
		assertFalse(
			result.output.contains("Unsupported class file major version"),
			"an analyzer cannot read the toolchain's class files; see CLAUDE.md rule 4 and docs/versions.md",
		)
	}

	private fun coveredInstructions(report: File, className: String): Int {
		val factory = DocumentBuilderFactory.newInstance()
		factory.setFeature("http://apache.org/xml/features/nonvalidating/load-external-dtd", false)
		val classes = factory.newDocumentBuilder().parse(report).getElementsByTagName("class")
		val element = (0 until classes.length).map { classes.item(it) as Element }.single { it.getAttribute("name") == className }
		return element.childElements("counter").single { it.getAttribute("type") == "INSTRUCTION" }.getAttribute("covered").toInt()
	}

	private fun Element.childElements(tagName: String): List<Element> =
		(0 until childNodes.length).map { childNodes.item(it) }.filterIsInstance<Element>().filter { it.tagName == tagName }

	private fun sbom(consumer: ConsumerFixture): String {
		val bom = consumer.file("build").walkTopDown().firstOrNull { file ->
			file.isFile && ((file.name.startsWith("bom") && file.name.endsWith(".json")) || file.name.endsWith(".cdx.json"))
		}
		assertTrue(bom != null, "cyclonedxBom must write bom*.json or *.cdx.json under build/, the pattern security-scan.yml looks for")
		return bom!!.readText()
	}

	private companion object {
		val EXECUTED = setOf(TaskOutcome.SUCCESS, TaskOutcome.UP_TO_DATE, TaskOutcome.FROM_CACHE)

		/** Bramki, które `build` konsumenta uruchamia w backend-ci.yml, plus SBOM ze security-scan.yml. */
		val CONSUMER_GATES = arrayOf(
			":platformDependencyCheck", ":spotlessCheck", ":checkstyleMain", ":checkstyleTest", ":spotbugsMain",
			":jacocoTestReport", ":jacocoTestCoverageVerification", ":platformCoverageDataCheck", ":platformRuntimeImageCheck",
			":cyclonedxBom",
		)

		/**
		 * Startuje spakowany bootJar z jego własnego classpathu. Testy widzą tylko testowy classpath, więc
		 * regresja wyłącznie runtime'owa (np. ArchUnit 1.4.2 na class-file 71 w v1.5.29) była dla nich niewidoczna.
		 * `spring.context.exit=onRefresh` kończy JVM zaraz po starcie kontekstu (kod 0, błąd startu = kod != 0):
		 * aplikacja trzyma nie-daemonowy wątek puli, więc bez tego proces nigdy by się nie zakończył. `Duration`
		 * wymaga importu dopisanego na początku skryptu: w skrypcie builda `java` to rozszerzenie, nie pakiet.
		 */
		const val SMOKE_START_BOOT_JAR = """
tasks.register<JavaExec>("smokeStartBootJar") {
    dependsOn("bootJar")
    classpath = files(tasks.named<org.springframework.boot.gradle.tasks.bundling.BootJar>("bootJar").flatMap { it.archiveFile })
    mainClass.set("org.springframework.boot.loader.launch.JarLauncher")
    javaLauncher.set(javaToolchains.launcherFor(java.toolchain))
    jvmArgs("-Dspring.context.exit=onRefresh")
    args("--spring.main.web-application-type=none")
    timeout.set(Duration.ofMinutes(3))
}
"""
	}
}
