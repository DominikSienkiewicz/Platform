package pl.seniordeveloper.gradle

import org.gradle.testkit.runner.TaskOutcome
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.nio.file.Path

/**
 * Governance z kanonem osadzonym w pluginie (E1-6), bez afterEvaluate (F-14), z raportem (N-DX-10), kodami bramek
 * (N-SHOW-8) i kanałem deprecacji (N-REL-9) — na opublikowanych konwencjach.
 */
class PlatformGovernanceFunctionalTest {
	@TempDir
	lateinit var directory: Path

	private val version = System.getProperty("platform.version")

	@Test
	fun `a catalog override in settings fails with PLAT-DEP-004 and the link to the release docs`() {
		val consumer = ConsumerFixture(directory, "java-library")
		editSettings(consumer) { line -> if ("platform-catalog:" in line) "$line\n\t\t\tversion(\"jsoup\", \"1.0.0\")" else line }

		val output = consumer.runner("platformDependencyCheck").buildAndFail().output

		assertTrue(output.contains("[PLAT-DEP-004] the libs catalog sets org.jsoup:jsoup to 1.0.0"), output)
		assertTrue(output.contains("/blob/v$version/docs/gates.md#plat-dep-004"), "the failure must link the docs of the release")
	}

	@Test
	fun `a build without a libs catalog fails closed with PLAT-DEP-005`() {
		val consumer = ConsumerFixture(directory, "java-library")
		editSettings(consumer) { it.replace("create(\"libs\")", "create(\"platformLibs\")") }
		consumer.file("build.gradle.kts").let { it.writeText(it.readText().replace("libs.", "platformLibs.")) }

		val output = consumer.runner("platformDependencyCheck").buildAndFail().output

		assertTrue(output.contains("[PLAT-DEP-005] seniordev.java-conventions requires a 'libs' version catalog"), output)
	}

	@Test
	fun `a dependency a late afterEvaluate adds is governed and reported in Markdown`() {
		val consumer = ConsumerFixture(directory, "java-library")
		consumer.appendToBuildScript("afterEvaluate { dependencies { \"implementation\"(\"org.jsoup:jsoup:1.0.0\") } }")
		val summary = directory.resolve("summary.md").toFile()
		val environment = System.getenv().toMutableMap().apply { put("GITHUB_STEP_SUMMARY", summary.path) }

		val result = consumer.runner("platformDependencyCheck").withEnvironment(environment).buildAndFail()

		assertEquals(TaskOutcome.FAILED, result.task(":platformDependencyCheck")?.outcome)
		assertTrue(result.output.contains("[PLAT-DEP-002] org.jsoup:jsoup:1.0.0 (implementation)"), result.output)
		val report = consumer.file("build/reports/platform/dependency-check.md").readText()
		assertTrue(report.contains("| [PLAT-DEP-002]("), report)
		assertTrue(summary.readText().contains("### platformDependencyCheck — :"), "the report must reach the job summary")
	}

	@Test
	fun `a consumer catalog appLibs with its own library passes and cannot override the canon`() {
		val consumer = ConsumerFixture(directory, "java-library")
		consumer.file("gradle/app.versions.toml").writeText(
			"""
			[libraries]
			own-library = "com.example:own-library:2.3.4"
			jsoup-other = "org.jsoup:jsoup:1.0.0"
			""".trimIndent(),
		)
		editSettings(consumer) { line ->
			if (line.trim() == "create(\"libs\") {") "\t\tcreate(\"appLibs\") { from(files(\"gradle/app.versions.toml\")) }\n$line" else line
		}
		consumer.appendToBuildScript("dependencies { implementation(appLibs.own.library) }")

		val passed = consumer.runner("platformDependencyCheck").build()
		consumer.appendToBuildScript("dependencies { implementation(appLibs.jsoup.other) }")
		val failed = consumer.runner("platformDependencyCheck").buildAndFail()

		assertEquals(TaskOutcome.SUCCESS, passed.task(":platformDependencyCheck")?.outcome)
		assertTrue(failed.output.contains("[PLAT-DEP-002] org.jsoup:jsoup:1.0.0 (implementation)"), failed.output)
	}

	@Test
	fun `a deprecated dependency warns, and fails only with platform deprecations fail`() {
		val consumer = ConsumerFixture(directory, "java-library")
		consumer.appendToBuildScript("dependencies { implementation(\"org.springframework.boot:spring-boot-starter-web\") }")

		val warned = consumer.runner("platformDependencyCheck", properties = mapOf("platform.deprecations.mode" to "warn")).build()
		val failed = consumer.runner("platformDependencyCheck").buildAndFail()

		assertTrue(
			warned.output.contains("[PLAT-DEPR-001] dependency org.springframework.boot:spring-boot-starter-web is deprecated"),
			warned.output,
		)
		assertEquals(TaskOutcome.FAILED, failed.task(":platformDependencyCheck")?.outcome)
		assertTrue(failed.output.contains("platform.deprecations.mode=fail and 1 deprecated item(s) remain"), failed.output)
	}

	@Test
	fun `a BOM import outside the frame warns and the build passes`() {
		val consumer = ConsumerFixture(directory, "java-library")
		consumer.appendToBuildScript("dependencies { implementation(platform(\"io.netty:netty-bom:4.2.0.Final\")) }")

		val result = consumer.runner("platformDependencyCheck").build()

		assertEquals(TaskOutcome.SUCCESS, result.task(":platformDependencyCheck")?.outcome)
		assertTrue(result.output.contains("BOM imports outside the Platform frame in : (1)"), result.output)
		assertTrue(result.output.contains("[PLAT-DEP-006] io.netty:netty-bom:4.2.0.Final (implementation)"), result.output)
	}

	private fun editSettings(
		consumer: ConsumerFixture,
		transform: (String) -> String,
	) {
		val settings = consumer.file("settings.gradle.kts")
		settings.writeText(settings.readLines().joinToString("\n", transform = transform))
	}
}
