package pl.seniordeveloper.gradle

import org.gradle.api.DefaultTask
import org.gradle.api.GradleException
import org.gradle.api.file.RegularFileProperty
import org.gradle.api.provider.ListProperty
import org.gradle.api.provider.Property
import org.gradle.api.tasks.Input
import org.gradle.api.tasks.InputFiles
import org.gradle.api.tasks.OutputFile
import org.gradle.api.tasks.PathSensitive
import org.gradle.api.tasks.PathSensitivity
import org.gradle.api.tasks.TaskAction
import org.gradle.work.DisableCachingByDefault
import java.io.File

/**
 * Bramka `platformRuntimeImageCheck`: ostatni `FROM` Dockerfile'a konsumenta (stage runtime) nie może
 * uruchamiać Javy starszej niż toolchain, w którym java-conventions kompiluje bytecode. Bez niej rozjazd
 * wychodził dopiero na health-gate po deployu jako UnsupportedClassVersionError.
 */
@DisableCachingByDefault(because = "Reads one small file; restoring the stamp from a cache costs more than the check")
abstract class RuntimeImageCheck : DefaultTask() {
	/** Kandydaci w kolejności: Dockerfile projektu, potem Dockerfile roota buildu (multi-module). */
	@get:InputFiles
	@get:PathSensitive(PathSensitivity.ABSOLUTE)
	abstract val dockerfiles: ListProperty<File>

	@get:Input
	abstract val toolchainVersion: Property<Int>

	/** Znacznik wyniku: bez wyjścia task wykonywałby się w każdym buildzie, także bez zmian (N-REL-15). */
	@get:OutputFile
	abstract val result: RegularFileProperty

	@TaskAction
	fun check() {
		val stamp = result.get().asFile.apply { parentFile.mkdirs() }
		stamp.delete()
		inspect()
		stamp.writeText("toolchain=${toolchainVersion.get()}\n")
	}

	private fun inspect() {
		val dockerfile = dockerfiles.get().firstOrNull { it.isFile }
		if (dockerfile == null) {
			logger.lifecycle("platformRuntimeImageCheck: skipped — no Dockerfile in the project or root directory")
			return
		}
		val toolchain = toolchainVersion.get()
		val image = RuntimeImage.finalStage(dockerfile.readText())
		val javaMajor = image?.javaMajor
		when {
			image == null -> {
				logger.lifecycle("platformRuntimeImageCheck: skipped — ${dockerfile.path} has no FROM line")
			}

			javaMajor == null -> {
				logger.lifecycle("platformRuntimeImageCheck: skipped — final image ${image.reference} is not a versioned JVM image")
			}

			javaMajor < toolchain -> {
				throw GradleException(
					"[${PlatformGates.IMAGE_OLDER_JAVA}] ${dockerfile.path} runs ${image.reference} (Java $javaMajor) in its final stage, but " +
						"seniordev.java-conventions compiles Java $toolchain bytecode, which needs a Java $toolchain runtime. " +
						"Change the final FROM to the image in templates/Dockerfile.backend of DominikSienkiewicz/Platform " +
						"(see docs/versions.md, section \"Runtime image for the JDK $toolchain toolchain\").\n" +
						PlatformGates.footer(listOf(PlatformGates.IMAGE_OLDER_JAVA)),
				)
			}

			else -> {
				logger.lifecycle("platformRuntimeImageCheck: OK — ${image.reference} runs Java $javaMajor, toolchain is $toolchain")
			}
		}
	}
}

/** Obraz ostatniego `FROM` i major Javy z jego tagu (sapmachine:27-jre → 27); `null`, gdy nie da się go ustalić. */
data class RuntimeImage(
	val reference: String,
	val javaMajor: Int?,
) {
	companion object {
		private val FROM = Regex("""^\s*FROM\s+(?:--platform=\S+\s+)?(\S+)""", setOf(RegexOption.IGNORE_CASE, RegexOption.MULTILINE))
		private val JVM_IMAGE_NAMES = listOf("temurin", "sapmachine", "openjdk", "corretto", "zulu", "liberica", "semeru")
		private val LEADING_MAJOR = Regex("""^(\d+)""")

		fun finalStage(dockerfile: String): RuntimeImage? {
			val reference =
				FROM
					.findAll(dockerfile)
					.lastOrNull()
					?.groupValues
					?.get(1) ?: return null
			return RuntimeImage(reference, javaMajor(reference))
		}

		private fun javaMajor(reference: String): Int? {
			if ('$' in reference) return null
			val lastSegment = reference.substringBefore('@').substringAfterLast('/')
			val name = lastSegment.substringBefore(':')
			val tag = lastSegment.substringAfter(':', missingDelimiterValue = "")
			val jvm = JVM_IMAGE_NAMES.any { it in name } || "jre" in tag || "jdk" in tag
			return if (jvm) {
				LEADING_MAJOR
					.find(tag)
					?.groupValues
					?.get(1)
					?.toInt()
			} else {
				null
			}
		}
	}
}
