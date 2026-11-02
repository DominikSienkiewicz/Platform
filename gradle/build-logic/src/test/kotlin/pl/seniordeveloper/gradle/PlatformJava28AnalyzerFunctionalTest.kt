package pl.seniordeveloper.gradle

import org.gradle.testkit.runner.TaskOutcome
import org.gradle.testkit.runner.UnexpectedBuildFailure
import org.junit.jupiter.api.Assertions.assertAll
import org.junit.jupiter.api.Assertions.assertDoesNotThrow
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.net.URLClassLoader
import java.nio.file.Path

class PlatformJava28AnalyzerFunctionalTest {
	@TempDir
	lateinit var directory: Path

	@Test
	fun `the configured analyzers instrument and read Java 28 class files`() {
		val consumer = ConsumerFixture(directory, "java-library")
		consumer.appendToBuildScript(
			"""
			tasks.register("jacocoClasspath") {
			    val classpath = configurations.named("jacocoAnt")
			    doLast { println("JACOCO_CLASSPATH:" + classpath.get().asPath) }
			}
			tasks.named<com.github.spotbugs.snom.SpotBugsTask>("spotbugsMain") {
			    reports.create("xml") {
			        required.set(true)
			        outputLocation.set(layout.buildDirectory.file("reports/spotbugs/main.xml"))
			    }
			}
			""".trimIndent(),
		)
		val compiled = consumer.runner("classes", "jacocoClasspath", "--no-configuration-cache").build()
		val classFile = consumer.file("build/classes/java/main/example/library/Greeting.class")
		val bytecode = classFile.readBytes()
		// Zmieniamy tylko major na 72: regresja czytników bajtkodu nie wymaga instalacji JDK EA ani wykonania klasy.
		bytecode[6] = 0
		bytecode[7] = 72
		classFile.writeBytes(bytecode)
		val jacocoClasspath =
			compiled.output
				.lineSequence()
				.single { it.startsWith("JACOCO_CLASSPATH:") }
				.removePrefix("JACOCO_CLASSPATH:")
		val urls = jacocoClasspath.split(File.pathSeparator).map { File(it).toURI().toURL() }.toTypedArray()

		// Osobny loader zachowuje ASM rzeczywistego narzędzia: ASM na classpath Gradle'a lub testu nie może go zastąpić.
		URLClassLoader(urls, ClassLoader.getPlatformClassLoader()).use { jacoco ->
			assertAll(
				{
					assertDoesNotThrow(
						{
							val generator = jacoco.loadClass("org.jacoco.core.runtime.OfflineInstrumentationAccessGenerator").getConstructor().newInstance()
							val instrumenter =
								jacoco
									.loadClass("org.jacoco.core.instr.Instrumenter")
									.getConstructor(jacoco.loadClass("org.jacoco.core.runtime.IExecutionDataAccessorGenerator"))
									.newInstance(generator)
							val instrumented =
								instrumenter.javaClass
									.getMethod("instrument", ByteArray::class.java, String::class.java)
									.invoke(instrumenter, bytecode, classFile.name) as ByteArray
							assertTrue(instrumented.size > bytecode.size, "JaCoCo must add probes to the Java 28 class")
						},
						"The configured JaCoCo must instrument class-file major 72",
					)
				},
				{
					assertDoesNotThrow(
						{
							val storeType = jacoco.loadClass("org.jacoco.core.data.ExecutionDataStore")
							val coverage = jacoco.loadClass("org.jacoco.core.analysis.CoverageBuilder").getConstructor().newInstance()
							val analyzer =
								jacoco
									.loadClass("org.jacoco.core.analysis.Analyzer")
									.getConstructor(storeType, jacoco.loadClass("org.jacoco.core.analysis.ICoverageVisitor"))
									.newInstance(storeType.getConstructor().newInstance(), coverage)
							analyzer.javaClass.getMethod("analyzeClass", ByteArray::class.java, String::class.java).invoke(analyzer, bytecode, classFile.name)
							val classes = coverage.javaClass.getMethod("getClasses").invoke(coverage) as Collection<*>
							assertEquals(1, classes.size, "JaCoCo must analyze the class used by its report and coverage gate")
						},
						"The configured JaCoCo must analyze class-file major 72",
					)
				},
				{
					val result =
						try {
							consumer.runner("spotbugsMain", "-x", "compileJava").build()
						} catch (failure: UnexpectedBuildFailure) {
							failure.buildResult
						}
					assertFalse(
						result.output.contains("Unsupported class file major version"),
						"SpotBugs must read class-file major 72:\n${result.output}",
					)
					assertEquals(TaskOutcome.SUCCESS, result.task(":spotbugsMain")?.outcome, result.output)
					val report = consumer.file("build/reports/spotbugs/main.xml").readText()
					assertTrue(report.contains("example.library.Greeting"), "SpotBugs must analyze the fixture class")
					assertTrue(report.contains("errors=\"0\""), "Report-only SpotBugs must not hide analysis errors: $report")
				},
			)
		}
	}
}
