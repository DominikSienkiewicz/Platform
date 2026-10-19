package pl.seniordeveloper.gradle

import org.gradle.testkit.runner.TaskOutcome
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.nio.file.Path

/** N-REL-15: drugi build bez zmian nie wykonuje żadnego taska konwencji od nowa. */
class PlatformIncrementalBuildFunctionalTest {
	@TempDir
	lateinit var directory: Path

	@Test
	fun `second build is incremental`() {
		val consumer = ConsumerFixture(directory, "java-library")
		consumer.runner("lint", "build").build()

		val again = consumer.runner("lint", "build").build()
		val executed =
			again.tasks
				.filter { it.outcome == TaskOutcome.SUCCESS }
				.map { it.path }
				.filterNot { it in ALWAYS_RUNS }
		assertTrue(executed.isEmpty(), "every task must be up to date in an unchanged second build, but these ran again: $executed")
	}

	private companion object {
		// Termin kwarantanny zależy od dnia, nie od wejść (PlatformQuarantineCheck), a taski cyklu życia, które od niego
		// zależą, raportują wtedy SUCCESS bez własnej pracy.
		val ALWAYS_RUNS = setOf(":platformQuarantineCheck", ":lint", ":check", ":build")
	}
}
