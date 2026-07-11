package pl.seniordeveloper.gradle

import com.puppycrawl.tools.checkstyle.Checker
import com.puppycrawl.tools.checkstyle.ConfigurationLoader
import com.puppycrawl.tools.checkstyle.PropertiesExpander
import com.puppycrawl.tools.checkstyle.api.AuditEvent
import com.puppycrawl.tools.checkstyle.api.AuditListener
import java.io.File
import java.util.Properties
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir

/**
 * Guard zgodności platform-checkstyle z google-java-format (Spotless).
 *
 * Spotless w seniordev.java-conventions formatuje kod przez googleJavaFormat(), a Checkstyle
 * weryfikuje TEN SAM kod. Każda konstrukcja, którą google-java-format wymusza, MUSI przechodzić
 * przez checkstyle.xml — inaczej konsument wpada w ping-pong: spotlessApply psuje checkstyle
 * i odwrotnie, bez żadnego formatowania spełniającego oba narzędzia.
 */
class PlatformCheckstyleConfigTest {

	@TempDir
	lateinit var tempDir: File

	@Test
	fun `pusta lambda w formacie google-java-format przechodzi checkstyle`() {
		// google-java-format renderuje pustą lambdę jako `() -> {}` (bez spacji w klamrach).
		val fixture = File(tempDir, "EmptyLambdaFixture.java")
		fixture.writeText(
			"""
			package pl.seniordeveloper.gradle.fixture;

			class EmptyLambdaFixture {
			  private final Runnable noop = () -> {};
			}
			""".trimIndent() + "\n",
		)

		val violations = runCheckstyle(fixture)

		assertTrue(
			violations.isEmpty(),
			"checkstyle.xml odrzuca kod w formacie google-java-format:\n" +
				violations.joinToString("\n") { "  ${it.sourceName}: ${it.message}" },
		)
	}

	private fun runCheckstyle(target: File): List<AuditEvent> {
		val configDir = File(tempDir, "checkstyle-config").apply { mkdirs() }
		listOf("checkstyle.xml", "checkstyle-suppressions.xml").forEach { name ->
			val resource = checkNotNull(javaClass.classLoader.getResourceAsStream("platform-checkstyle/$name")) {
				"Brak zasobu platform-checkstyle/$name na classpath testu"
			}
			resource.use { File(configDir, name).writeBytes(it.readBytes()) }
		}

		val properties = Properties().apply { setProperty("config_loc", configDir.absolutePath) }
		val configuration = ConfigurationLoader.loadConfiguration(
			File(configDir, "checkstyle.xml").absolutePath,
			PropertiesExpander(properties),
		)

		val errors = mutableListOf<AuditEvent>()
		val listener = object : AuditListener {
			override fun auditStarted(event: AuditEvent) { }

			override fun auditFinished(event: AuditEvent) { }

			override fun fileStarted(event: AuditEvent) { }

			override fun fileFinished(event: AuditEvent) { }

			override fun addError(event: AuditEvent) {
				errors += event
			}

			override fun addException(event: AuditEvent, throwable: Throwable) {
				throw IllegalStateException("Checkstyle rzucił wyjątek dla ${event.fileName}", throwable)
			}
		}

		val checker = Checker()
		try {
			checker.setModuleClassLoader(Checker::class.java.classLoader)
			checker.configure(configuration)
			checker.addListener(listener)
			checker.process(listOf(target))
		} finally {
			checker.destroy()
		}
		return errors
	}
}
