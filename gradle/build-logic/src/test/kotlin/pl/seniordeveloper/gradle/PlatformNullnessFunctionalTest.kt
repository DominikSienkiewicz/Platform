package pl.seniordeveloper.gradle

import org.gradle.testkit.runner.TaskOutcome
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.nio.file.Path

/** N-CAP-11: NullAway w trybie JSpecify sprawdza tylko pakiety @NullMarked, także na toolchainie kanonu. */
class PlatformNullnessFunctionalTest {
	@TempDir
	lateinit var directory: Path

	@Test
	fun `a NullMarked package that dereferences a Nullable return fails compileJava`() {
		val consumer = nullnessConsumer()
		consumer.file("src/main/java/example/library/nullness/package-info.java").writeText(
			"@NullMarked\npackage example.library.nullness;\n\nimport org.jspecify.annotations.NullMarked;\n",
		)

		val result = consumer.runner("compileJava").buildAndFail()
		assertEquals(TaskOutcome.FAILED, result.task(":compileJava")?.outcome)
		assertTrue(result.output.contains("[NullAway]"), "the failure must be a NullAway diagnostic")
		assertTrue(result.output.contains("Lookup.java"), "the diagnostic must name the file")
	}

	@Test
	fun `the same code outside a NullMarked package compiles`() {
		val consumer = nullnessConsumer()

		val result = consumer.runner("compileJava").build()
		assertEquals(TaskOutcome.SUCCESS, result.task(":compileJava")?.outcome)
	}

	private fun nullnessConsumer(): ConsumerFixture {
		val consumer = ConsumerFixture(directory, "java-library")
		val script = consumer.file("build.gradle.kts")
		script.writeText(
			script
				.readText()
				.replace(
					"\tid(\"seniordev.quality-conventions\")\n",
					"\tid(\"seniordev.quality-conventions\")\n\tid(\"seniordev.nullness-conventions\")\n",
				),
		)
		consumer.appendToBuildScript("dependencies {\n    implementation(libs.jspecify)\n}")
		File(consumer.file("src/main/java/example/library/nullness"), "Lookup.java").apply {
			parentFile.mkdirs()
			writeText(
				"""
				package example.library.nullness;

				import org.jspecify.annotations.Nullable;

				public final class Lookup {
				  private Lookup() {}

				  static @Nullable String find(String key) {
				    return key.isEmpty() ? null : key;
				  }

				  public static int length(String key) {
				    return find(key).length();
				  }
				}
				""".trimIndent() + "\n",
			)
		}
		return consumer
	}
}
