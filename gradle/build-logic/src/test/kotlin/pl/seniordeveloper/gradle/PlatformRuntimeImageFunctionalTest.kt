package pl.seniordeveloper.gradle

import org.gradle.testkit.runner.TaskOutcome
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.nio.file.Path

/** platformRuntimeImageCheck na opublikowanych konwencjach: obraz runtime nie może być starszy niż toolchain. */
class PlatformRuntimeImageFunctionalTest {
	@TempDir
	lateinit var directory: Path

	@Test
	fun `a final image older than the toolchain fails with the canonical fix`() {
		val consumer = ConsumerFixture(directory, "spring-app")
		consumer.file("Dockerfile").writeText("FROM eclipse-temurin:26-jre\nCOPY build/libs/*.jar /app.jar\n")

		val result = consumer.runner("platformRuntimeImageCheck").buildAndFail()

		assertEquals(TaskOutcome.FAILED, result.task(":platformRuntimeImageCheck")?.outcome)
		assertTrue(result.output.contains("runs eclipse-temurin:26-jre (Java 26) in its final stage"), "the message must name the image")
		assertTrue(result.output.contains("Change the final FROM to the image in templates/Dockerfile.backend"), "the message must name the fix")
	}

	@Test
	fun `a multi-stage build is judged by its final stage`() {
		val consumer = ConsumerFixture(directory, "spring-app")
		consumer.file("Dockerfile").writeText(
			"""
			FROM curlimages/curl:8.21.0 AS embedding-model
			RUN echo model > /model.onnx

			FROM sapmachine:27-jre
			COPY --from=embedding-model /model.onnx /model.onnx
			""".trimIndent(),
		)

		val result = consumer.runner("platformRuntimeImageCheck").build()

		assertEquals(TaskOutcome.SUCCESS, result.task(":platformRuntimeImageCheck")?.outcome)
		assertTrue(result.output.contains("platformRuntimeImageCheck: OK — sapmachine:27-jre runs Java 27"))
	}
}
