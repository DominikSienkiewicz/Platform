package pl.seniordeveloper.gradle

import org.gradle.api.DefaultTask
import org.gradle.api.GradleException
import org.gradle.api.file.RegularFileProperty
import org.gradle.api.provider.ListProperty
import org.gradle.api.provider.MapProperty
import org.gradle.api.provider.Property
import org.gradle.api.provider.SetProperty
import org.gradle.api.tasks.Input
import org.gradle.api.tasks.OutputFile
import org.gradle.api.tasks.TaskAction
import org.gradle.work.DisableCachingByDefault

/**
 * Bramka `platformDependencyCheck` (F-14): wartości zbierają providery, które Gradle wylicza po konfiguracji
 * projektu — także zależności dopisane w późniejszym `afterEvaluate` — więc nie ma tu żadnego afterEvaluate.
 * Raport Markdown trafia do build/reports/platform/dependency-check.md i do $GITHUB_STEP_SUMMARY (N-DX-10).
 */
@DisableCachingByDefault(because = "Verification with a small report; cheaper to rerun than to cache")
abstract class PlatformDependencyCheck : DefaultTask() {
	@get:Input
	abstract val projectPath: Property<String>

	@get:Input
	abstract val declared: ListProperty<String>

	@get:Input
	abstract val canon: MapProperty<String, String>

	@get:Input
	abstract val catalogPresent: Property<Boolean>

	@get:Input
	abstract val consumerCatalog: MapProperty<String, String>

	@get:Input
	abstract val bomManaged: MapProperty<String, String>

	@get:Input
	abstract val deprecations: ListProperty<String>

	/** Każdy zadeklarowany moduł, także bez wersji (zarządzany BOM-em) — dla kanału deprecacji. */
	@get:Input
	abstract val declaredModules: SetProperty<String>

	@get:Input
	abstract val propertiesSet: SetProperty<String>

	@get:Input
	abstract val pluginsApplied: SetProperty<String>

	@get:Input
	abstract val failOnDeprecation: Property<Boolean>

	/** `group:name` dokładane z wersją przez sam Gradle (DependencyGovernance.GRADLE_INJECTED). */
	@get:Input
	abstract val exempt: SetProperty<String>

	@get:OutputFile
	abstract val report: RegularFileProperty

	@TaskAction
	fun check() {
		val dependencies = declared.get().map(DeclaredDependency::decode)
		val canonEntries = canon.get().mapValues { (_, value) -> value.split('\t').let { CanonEntry(it[0], it[1]) } }
		val findings =
			if (!catalogPresent.get()) {
				listOf(DependencyGovernance.noCatalog())
			} else {
				DependencyGovernance.catalogOverrides(consumerCatalog.get(), canonEntries) +
					DependencyGovernance.violations(dependencies, canonEntries, bomManaged.get(), exempt.get())
			}
		val deprecated =
			PlatformDeprecations.findings(
				deprecations.get().map(PlatformDeprecations::decode),
				declaredModules.get(),
				propertiesSet.get(),
				pluginsApplied.get(),
			)
		val markdown = DependencyGovernance.report(projectPath.get(), findings, deprecated)
		report.get().asFile.apply {
			parentFile.mkdirs()
			writeText(markdown)
		}
		// Odczyt w akcji, nie w konfiguracji: configuration cache nie śledzi wtedy tej zmiennej środowiskowej.
		System.getenv("GITHUB_STEP_SUMMARY")?.takeIf { it.isNotBlank() && (findings.isNotEmpty() || deprecated.isNotEmpty()) }?.let {
			java.io.File(it).appendText(markdown + "\n")
		}
		if (deprecated.isNotEmpty()) {
			logger.warn(
				"Platform deprecations in ${projectPath.get()} (${deprecated.size}):\n  " + deprecated.joinToString("\n  ") { it.render() } +
					"\n" + PlatformGates.footer(deprecated.map { it.code }),
			)
		}
		if (findings.isNotEmpty()) {
			throw GradleException(
				"Dependency versions outside the Platform canon (platformDependencyCheck):\n  " +
					findings.joinToString("\n  ") { it.render() } + "\n" + PlatformGates.footer(findings.map { it.code }) +
					"\nReport: ${report.get().asFile.path}",
			)
		}
		if (deprecated.isNotEmpty() && failOnDeprecation.get()) {
			throw GradleException(
				"platform.deprecations.mode=fail and ${deprecated.size} deprecated item(s) remain; see the warning above " +
					"and ${report.get().asFile.path}",
			)
		}
		logger.lifecycle("platformDependencyCheck: OK — every explicit version matches platform-catalog")
	}
}
