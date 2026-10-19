package pl.seniordeveloper.gradle

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

class RuntimeImageTest {
	@Test
	fun `reads the Java major of the canonical runtime image`() {
		assertEquals(RuntimeImage("sapmachine:27-jre", 27), RuntimeImage.finalStage("FROM sapmachine:27-jre\n"))
	}

	@Test
	fun `takes the last stage of a multi-stage build`() {
		val dockerfile =
			"""
			FROM curlimages/curl:8.21.0 AS embedding-model
			RUN curl -o /model.onnx https://example.invalid/model.onnx

			FROM eclipse-temurin:26-jre
			COPY --from=embedding-model /model.onnx /model.onnx
			""".trimIndent()

		assertEquals(RuntimeImage("eclipse-temurin:26-jre", 26), RuntimeImage.finalStage(dockerfile))
	}

	@Test
	fun `understands registries, platform flags and digests`() {
		assertEquals(
			27,
			RuntimeImage
				.finalStage(
					"from --platform=linux/amd64 registry.example:5000/library/eclipse-temurin:27-jre@sha256:abc AS runtime",
				)?.javaMajor,
		)
		assertEquals(21, RuntimeImage.finalStage("FROM amazoncorretto:21.0.4-al2023")?.javaMajor)
	}

	@Test
	fun `leaves images it cannot version unchecked`() {
		assertNull(RuntimeImage.finalStage("FROM \${BASE_IMAGE}")?.javaMajor, "a build argument cannot be resolved statically")
		assertNull(RuntimeImage.finalStage("FROM nginx:1.27-alpine")?.javaMajor, "a non-JVM image has no Java major")
		assertNull(RuntimeImage.finalStage("FROM eclipse-temurin:latest")?.javaMajor, "a JVM image without a versioned tag has no Java major")
		assertNull(RuntimeImage.finalStage("# no stages here"))
	}
}
