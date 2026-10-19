package pl.seniordeveloper.gradle

import com.puppycrawl.tools.checkstyle.Checker
import com.puppycrawl.tools.checkstyle.ConfigurationLoader
import com.puppycrawl.tools.checkstyle.PropertiesExpander
import com.puppycrawl.tools.checkstyle.api.AuditEvent
import com.puppycrawl.tools.checkstyle.api.AuditListener
import java.io.File
import java.util.Properties

/** Uruchamia platform-checkstyle z zasobów build-logic na plikach i zwraca naruszenia. */
internal object CheckstyleAudit {
	fun violations(
		workDir: File,
		files: List<File>,
	): List<AuditEvent> {
		val configDir = File(workDir, "checkstyle-config").apply { mkdirs() }
		listOf("checkstyle.xml", "checkstyle-suppressions.xml").forEach { name ->
			val resource =
				checkNotNull(javaClass.classLoader.getResourceAsStream("platform-checkstyle/$name")) {
					"Brak zasobu platform-checkstyle/$name na classpath testu"
				}
			resource.use { File(configDir, name).writeBytes(it.readBytes()) }
		}
		val properties = Properties().apply { setProperty("config_loc", configDir.absolutePath) }
		val configuration =
			ConfigurationLoader.loadConfiguration(
				File(configDir, "checkstyle.xml").absolutePath,
				PropertiesExpander(properties),
			)
		val errors = mutableListOf<AuditEvent>()
		val checker = Checker()
		try {
			checker.setModuleClassLoader(Checker::class.java.classLoader)
			checker.configure(configuration)
			checker.addListener(Collector(errors))
			checker.process(files)
		} finally {
			checker.destroy()
		}
		return errors
	}

	fun describe(events: List<AuditEvent>): String =
		events.joinToString("\n") { "  ${File(it.fileName).name}:${it.line} ${it.sourceName.substringAfterLast('.')}: ${it.message}" }

	private class Collector(
		private val errors: MutableList<AuditEvent>,
	) : AuditListener {
		override fun auditStarted(event: AuditEvent) {
			// Zdarzenie cyklu życia audytu, bez naruszenia.
		}

		override fun auditFinished(event: AuditEvent) {
			// Zdarzenie cyklu życia audytu, bez naruszenia.
		}

		override fun fileStarted(event: AuditEvent) {
			// Zdarzenie cyklu życia pliku, bez naruszenia.
		}

		override fun fileFinished(event: AuditEvent) {
			// Zdarzenie cyklu życia pliku, bez naruszenia.
		}

		override fun addError(event: AuditEvent) {
			errors += event
		}

		override fun addException(
			event: AuditEvent,
			throwable: Throwable,
		): Unit = throw IllegalStateException("Checkstyle rzucił wyjątek dla ${event.fileName}", throwable)
	}
}
