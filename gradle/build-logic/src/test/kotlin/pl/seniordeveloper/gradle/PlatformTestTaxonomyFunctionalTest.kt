package pl.seniordeveloper.gradle

import org.gradle.testkit.runner.TaskOutcome
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.nio.file.Path

/** Taksonomia testów (N-CAP-8), kwarantanna z terminem i wykrywanie niestabilnych testów (N-REL-13). */
class PlatformTestTaxonomyFunctionalTest {
	@TempDir
	lateinit var directory: Path

	@Test
	fun `every test task names itself and check leaves model and quarantine tests out`() {
		val consumer = ConsumerFixture(directory, "spring-app")
		consumer.appendToBuildScript(
			"""
			tasks.register("inspectTaxonomy") {
			    val names = listOf("test", "integrationTest", "modelTest", "quarantineTest")
			    val seen = names.associateWith { tasks.named<Test>(it).get().systemProperties["platform.test.task"] }
			    doLast { seen.forEach { (task, property) -> println("TASK:${'$'}task=${'$'}property") } }
			}
			""".trimIndent(),
		)

		val inspected = consumer.runner("inspectTaxonomy").build()
		listOf("test", "integrationTest", "modelTest", "quarantineTest").forEach { task ->
			assertTrue(inspected.output.contains("TASK:$task=$task"), "$task must pass its name to PlatformTestTaskGuard")
		}

		val plan = consumer.runner("check", "--dry-run").build().output
		assertTrue(plan.contains(":integrationTest SKIPPED"), "check must run integrationTest")
		assertTrue(plan.contains(":platformQuarantineCheck SKIPPED"), "check must run platformQuarantineCheck")
		assertFalse(plan.contains(":modelTest"), "modelTest must stay outside check")
		assertFalse(plan.contains(":quarantineTest"), "quarantineTest must stay outside check")
	}

	@Test
	fun `a quarantined test runs only in quarantineTest and never fails the build`() {
		val consumer = ConsumerFixture(directory, "java-library")
		quarantinedTest(consumer, "// quarantine: https://github.com/example/library/issues/1 until 2099-12-31")

		val build = consumer.runner("test", "platformQuarantineCheck").build()
		assertEquals(TaskOutcome.SUCCESS, build.task(":test")?.outcome)
		assertTrue(build.output.contains("platformQuarantineCheck: 1 quarantined test(s)"))
		assertFalse(consumer.file("build/test-results/test/TEST-example.library.FlakyTest.xml").exists(), "test must skip the quarantine tag")

		val quarantine = consumer.runner("quarantineTest").build()
		assertEquals(TaskOutcome.SUCCESS, quarantine.task(":quarantineTest")?.outcome)
		val report = consumer.file("build/test-results/quarantineTest/TEST-example.library.FlakyTest.xml")
		assertTrue(report.readText().contains("<failure"), "quarantineTest must still run and report the quarantined test")
	}

	@Test
	fun `quarantine without an issue and a date fails and an expired one fails on CI only`() {
		val consumer = ConsumerFixture(directory, "java-library")
		quarantinedTest(consumer, "// flaky on CI")
		val untracked = consumer.runner("platformQuarantineCheck").buildAndFail()
		assertTrue(untracked.output.contains("[PLAT-QUA-001]"), "a quarantine without a deadline must fail")
		assertTrue(untracked.output.contains("FlakyTest.java:"), "the message must name the file")

		quarantinedTest(consumer, "// quarantine: https://github.com/example/library/issues/1 until 2026-01-31")
		val today = mapOf("platform.quarantineToday" to "2026-02-01")
		val local = consumer.runner("platformQuarantineCheck", properties = today).withEnvironment(environment(ci = false)).build()
		assertTrue(local.output.contains("Expired quarantine (fails on CI)"), "an expired quarantine must warn locally")

		val ci = consumer.runner("platformQuarantineCheck", properties = today).withEnvironment(environment(ci = true)).buildAndFail()
		assertTrue(ci.output.contains("[PLAT-QUA-002]"), "an expired quarantine must fail on CI")
		assertTrue(ci.output.contains("docs/gates.md#plat-qua-002"), "the message must link the gate code")
	}

	@Test
	fun `retry detection keeps a test that passed on retry red`() {
		val consumer = ConsumerFixture(directory, "java-library")
		consumer.file("src/test/java/example/library/RetriedTest.java").writeText(
			"""
			package example.library;

			import static org.junit.jupiter.api.Assertions.assertTrue;

			import java.io.IOException;
			import java.nio.file.Files;
			import java.nio.file.Path;
			import org.junit.jupiter.api.Test;

			class RetriedTest {
			  @Test
			  void passesOnTheSecondAttempt() throws IOException {
			    Path marker = Path.of("build", "retried-once");
			    boolean firstAttempt = !Files.exists(marker);
			    Files.createDirectories(marker.getParent());
			    Files.writeString(marker, "seen");
			    assertTrue(!firstAttempt, "fails on the first attempt only");
			  }
			}
			""".trimIndent() + "\n",
		)

		// Ta sama droga, którą idzie backend-ci.yml: zmienna środowiskowa, argumenty Gradle'a bez zmian.
		val ciEnvironment = System.getenv().toMutableMap().apply { put("PLATFORM_TEST_RETRY", "detect") }
		val detected = consumer.runner("test").withEnvironment(ciEnvironment).buildAndFail()
		assertEquals(TaskOutcome.FAILED, detected.task(":test")?.outcome)
		val report = consumer.file("build/test-results/test/TEST-example.library.RetriedTest.xml").readText()
		assertTrue(report.contains("<failure"), "the report must keep the failed first attempt:\n$report")
		assertEquals(2, Regex("""<testcase name="passesOnTheSecondAttempt\(\)"""").findAll(report).count(), "the retry must be in the report")
	}

	private fun quarantinedTest(
		consumer: ConsumerFixture,
		comment: String,
	) {
		consumer.file("src/test/java/example/library/FlakyTest.java").writeText(
			"""
			package example.library;

			import static org.junit.jupiter.api.Assertions.fail;

			import org.junit.jupiter.api.Tag;
			import org.junit.jupiter.api.Test;

			class FlakyTest {
			  $comment
			  @Tag("quarantine")
			  @Test
			  void failsUntilFixed() {
			    fail("known flaky");
			  }
			}
			""".trimIndent() + "\n",
		)
	}

	private fun environment(ci: Boolean): Map<String, String> =
		System.getenv().toMutableMap().apply {
			if (ci) put("CI", "true") else remove("CI")
		}
}
