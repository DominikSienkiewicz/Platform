package pl.seniordeveloper.gradle

import org.gradle.api.DefaultTask
import org.gradle.api.GradleException
import org.gradle.api.provider.Property
import org.gradle.api.tasks.Input
import org.gradle.api.tasks.Optional
import org.gradle.api.tasks.TaskAction
import org.gradle.jvm.toolchain.JavaLanguageVersion
import org.gradle.jvm.toolchain.JavaToolchainService
import org.gradle.work.DisableCachingByDefault
import java.math.BigDecimal
import javax.inject.Inject

/**
 * `platformDoctor` (N-DX-1): strona Gradle diagnozy repo konsumenta — to, czego bin `platform-doctor` nie widzi
 * z tekstu plików. Format wierszy i ID (PD08x) są te same co w binie; każde ID ma wiersz w docs/consuming.md
 * (Troubleshooting). Wartości zbiera konfiguracja, więc task jest zgodny z configuration cache.
 */
@DisableCachingByDefault(because = "Diagnoses the build and produces no output")
abstract class PlatformDoctor : DefaultTask() {
	@get:Input
	abstract val pluginVersion: Property<String>

	@get:Input
	@get:Optional
	abstract val catalogVersion: Property<String>

	@get:Input
	@get:Optional
	abstract val platformVersionProperty: Property<String>

	@get:Input
	@get:Optional
	abstract val coverageMinimum: Property<String>

	@get:Input
	@get:Optional
	abstract val toolchainLanguageVersion: Property<Int>

	@get:Inject
	abstract val toolchains: JavaToolchainService

	@TaskAction
	fun diagnose() {
		val findings =
			listOf(
				DoctorChecks.pins(pluginVersion.get(), catalogVersion.orNull, platformVersionProperty.orNull),
				DoctorChecks.toolchain(toolchainLanguageVersion.orNull, ::resolveToolchain),
				DoctorChecks.coverageMinimum(coverageMinimum.orNull),
			)
		// quiet, nie lifecycle: bin platform-doctor woła task z -q i przekazuje te wiersze dalej.
		findings.forEach { logger.quiet(it.render()) }
		val failed = findings.count { it.status == DoctorFinding.Status.FAIL }
		if (failed > 0) {
			throw GradleException("$failed platformDoctor check(s) failed; the IDs are explained in docs/consuming.md (Troubleshooting).")
		}
	}

	private fun resolveToolchain(languageVersion: Int): String =
		toolchains
			.launcherFor { this.languageVersion.set(JavaLanguageVersion.of(languageVersion)) }
			.get()
			.metadata.installationPath.asFile.path
}

/** Jeden wiersz diagnozy: status, stabilne ID, co widać i naprawa. */
data class DoctorFinding(
	val status: Status,
	val id: String,
	val message: String,
	val fix: String? = null,
) {
	enum class Status { PASS, WARN, FAIL }

	fun render(): String = "%-4s %s %s".format(status, id, message) + (fix?.let { "\n          fix: $it" } ?: "")
}

/** Logika sprawdzeń bez Gradle'a, testowana jednostkowo (PlatformDoctorTest). */
object DoctorChecks {
	fun pins(
		pluginVersion: String,
		catalogVersion: String?,
		platformVersionProperty: String?,
	): DoctorFinding {
		if (catalogVersion == null) {
			return DoctorFinding(
				DoctorFinding.Status.FAIL,
				"PD080",
				"the build loads no version catalog libs from platform-catalog",
				"""add versionCatalogs { create("libs") { from("pl.seniordeveloper:platform-catalog:<version>") } } to settings.gradle.kts as docs/consuming.md shows""",
			)
		}
		val pins =
			listOfNotNull(
				"seniordev.settings-conventions" to pluginVersion,
				"platform-catalog" to catalogVersion,
				platformVersionProperty?.let { "platformVersion" to it.trim() },
			)
		if (pins.map { it.second }.distinct().size == 1) {
			return DoctorFinding(DoctorFinding.Status.PASS, "PD080", "${pins.joinToString(", ") { it.first }} are all $pluginVersion")
		}
		return DoctorFinding(
			DoctorFinding.Status.FAIL,
			"PD080",
			"the Gradle-side Platform pins disagree: ${pins.joinToString(", ") { "${it.first} ${it.second}" }}",
			"run scripts/platform-bump.sh <version>, or read both pins from platformVersion in settings.gradle.kts as docs/consuming.md shows",
		)
	}

	fun toolchain(
		languageVersion: Int?,
		resolve: (Int) -> String,
	): DoctorFinding {
		if (languageVersion == null) {
			return DoctorFinding(DoctorFinding.Status.PASS, "PD081", "the root project sets no Java toolchain")
		}
		return try {
			DoctorFinding(DoctorFinding.Status.PASS, "PD081", "the Java $languageVersion toolchain resolves to ${resolve(languageVersion)}")
		} catch (e: Exception) {
			DoctorFinding(
				DoctorFinding.Status.FAIL,
				"PD081",
				"no Java $languageVersion toolchain: ${e.message?.lineSequence()?.firstOrNull() ?: e.javaClass.simpleName}",
				"install JDK $languageVersion, or allow Gradle to provision it (org.gradle.java.installations.auto-download, docs/versions.md)",
			)
		}
	}

	fun coverageMinimum(raw: String?): DoctorFinding {
		if (raw == null) {
			return DoctorFinding(
				DoctorFinding.Status.WARN,
				"PD082",
				"coverageMinimum is not set, so the coverage gate accepts any coverage (0.00)",
				"set coverageMinimum in gradle.properties to the coverage the code has today and raise it towards 0.80",
			)
		}
		val value = raw.trim().toBigDecimalOrNull()?.takeIf { it >= BigDecimal.ZERO && it <= BigDecimal.ONE }
		return if (value == null) {
			DoctorFinding(
				DoctorFinding.Status.FAIL,
				"PD082",
				"coverageMinimum is '$raw', not a decimal between 0 and 1",
				"write it as a fraction, for example coverageMinimum=0.80",
			)
		} else {
			DoctorFinding(DoctorFinding.Status.PASS, "PD082", "coverageMinimum is ${value.toPlainString()}")
		}
	}
}
