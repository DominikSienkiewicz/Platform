package pl.seniordeveloper.gradle

import org.gradle.api.DefaultTask
import org.gradle.api.GradleException
import org.gradle.api.file.RegularFileProperty
import org.gradle.api.provider.Property
import org.gradle.api.tasks.Input
import org.gradle.api.tasks.Optional
import org.gradle.api.tasks.OutputFile
import org.gradle.api.tasks.TaskAction
import org.gradle.work.DisableCachingByDefault

/**
 * Bramka `platformPinCheck` (N-DX-13): settings plugin i platform-catalog przypięte do różnych wydań. Convention
 * pluginy nakładają wtedy BOM-y i narzędzia jednego wydania na kanon drugiego, a pozostałe bramki padają z mylącym
 * komunikatem — ten task nazywa prawdziwą przyczynę. To samo porównanie robi PD080 w `platformDoctor`.
 */
@DisableCachingByDefault(because = "Compares two versions; restoring the stamp from a cache costs more than the comparison")
abstract class PlatformPinCheck : DefaultTask() {
	@get:Input
	abstract val pluginVersion: Property<String>

	@get:Input
	@get:Optional
	abstract val catalogVersion: Property<String>

	/** Znacznik wyniku: bez wyjścia task wykonywałby się w każdym buildzie, także bez zmian (N-REL-15). */
	@get:OutputFile
	abstract val result: RegularFileProperty

	@TaskAction
	fun check() {
		val plugin = pluginVersion.get()
		val catalog = catalogVersion.orNull
		result.get().asFile.apply {
			parentFile.mkdirs()
			delete()
		}
		when {
			catalog == null -> {
				logger.lifecycle("platformPinCheck: skipped — no 'libs' catalog with a platform version, so this is not a Platform consumer build")
			}

			catalog != plugin -> {
				throw GradleException(
					PlatformGates.line(PlatformGates.PIN_DIVERGE, mismatch(plugin, catalog)) + "\n" +
						PlatformGates.footer(listOf(PlatformGates.PIN_DIVERGE)),
				)
			}

			else -> {
				logger.lifecycle("platformPinCheck: OK — the settings plugin and platform-catalog are both $plugin")
			}
		}
		result.get().asFile.writeText("plugin=$plugin catalog=${catalog ?: "none"}\n")
	}

	companion object {
		fun mismatch(
			plugin: String,
			catalog: String,
		): String =
			"The Platform pins diverge: seniordev.settings-conventions is $plugin, platform-catalog is $catalog. The conventions " +
				"then apply the BOMs and tools of $plugin to the canon of $catalog, so other gates fail for the wrong reason. " +
				"Align both pins with scripts/platform-bump.sh $catalog, or read both from platformVersion in " +
				"settings.gradle.kts (docs/consuming.md)."
	}
}
