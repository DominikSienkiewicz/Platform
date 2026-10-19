package pl.seniordeveloper.gradle

import org.gradle.api.DefaultTask
import org.gradle.api.GradleException
import org.gradle.api.file.ConfigurableFileCollection
import org.gradle.api.file.RegularFileProperty
import org.gradle.api.provider.Property
import org.gradle.api.tasks.Input
import org.gradle.api.tasks.InputFiles
import org.gradle.api.tasks.Optional
import org.gradle.api.tasks.OutputFile
import org.gradle.api.tasks.PathSensitive
import org.gradle.api.tasks.PathSensitivity
import org.gradle.api.tasks.TaskAction
import org.gradle.work.DisableCachingByDefault
import java.time.LocalDate

/** Bramka `platformQuarantineCheck` (N-REL-13) — reguły w [QuarantineRules]. */
@DisableCachingByDefault(because = "Reads test sources and compares dates with today")
abstract class PlatformQuarantineCheck : DefaultTask() {
	@get:InputFiles
	@get:PathSensitive(PathSensitivity.RELATIVE)
	abstract val sources: ConfigurableFileCollection

	@get:Input
	abstract val ci: Property<Boolean>

	/** Tylko testy Platform: data „dziś” zamiast zegara. */
	@get:Input
	@get:Optional
	abstract val today: Property<String>

	@get:OutputFile
	abstract val report: RegularFileProperty

	init {
		// Data wygaśnięcia zależy od dnia, nie od wejść, więc wynik z wczoraj nie jest aktualny dziś.
		outputs.upToDateWhen { false }
	}

	@TaskAction
	fun check() {
		val testSources = mutableListOf<Pair<String, java.io.File>>()
		sources.asFileTree.visit {
			if (!isDirectory && (name.endsWith(".java") || name.endsWith(".kt"))) testSources += relativePath.pathString to file
		}
		val entries = testSources.sortedBy { it.first }.flatMap { (path, file) -> QuarantineRules.scan(path, file.readText()) }
		val now = today.orNull?.let(LocalDate::parse) ?: LocalDate.now()
		val missing = QuarantineRules.missing(entries)
		val expired = QuarantineRules.expired(entries, now)
		report.get().asFile.apply {
			parentFile.mkdirs()
			writeText(
				entries.joinToString("\n", postfix = if (entries.isEmpty()) "" else "\n") {
					"${it.file}:${it.line} ${it.issue ?: "-"} ${it.until ?: "-"}"
				},
			)
		}
		val failing = missing + if (ci.get()) expired else emptyList()
		if (!ci.get() && expired.isNotEmpty()) {
			logger.warn("Expired quarantine (fails on CI):\n  " + expired.joinToString("\n  ") { it.render() })
		}
		if (failing.isNotEmpty()) {
			throw GradleException(
				"Quarantined tests without a tracked deadline (platformQuarantineCheck):\n  " + failing.joinToString("\n  ") { it.render() } +
					"\n" + PlatformGates.footer(failing.map { it.code }),
			)
		}
		logger.lifecycle("platformQuarantineCheck: ${entries.size} quarantined test(s), each with an issue and a date")
	}
}
