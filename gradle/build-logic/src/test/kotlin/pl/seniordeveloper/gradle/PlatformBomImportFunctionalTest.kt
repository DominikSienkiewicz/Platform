package pl.seniordeveloper.gradle

import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.nio.file.Path

/**
 * N-CAP-12: spring-modulith-conventions importuje pl.seniordeveloper:platform-bom zamiast własnych BOM-ów i `ext`.
 * dependencyInsight na starterze spring-app pokazuje podłogi i nadpisania BOM-u — także wtedy, gdy konsument
 * ustawia własną `jackson-bom.version`, której import Jacksona w platform-bom (przed Bootem) nie oddaje.
 */
class PlatformBomImportFunctionalTest {
	@TempDir
	lateinit var directory: Path

	@Test
	fun `the platform BOM selects the compatibility override and the CVE floors`() {
		val consumer = ConsumerFixture(directory, "spring-app")
		consumer.appendToBuildScript("dependencies { compileOnly(\"org.projectlombok:lombok\") }")

		val lombok = insight(consumer, "lombok", "compileClasspath")
		val jackson = insight(consumer, "jackson-databind", "runtimeClasspath")
		val tomcat = insight(consumer, "tomcat-embed-core", "runtimeClasspath")

		assertTrue(lombok.contains("org.projectlombok:lombok:${canon("lombok")}"), lombok)
		assertTrue(jackson.contains("tools.jackson.core:jackson-databind:${canon("jacksonBom")}"), jackson)
		assertTrue(tomcat.contains("org.apache.tomcat.embed:tomcat-embed-core:${canon("tomcat")}"), tomcat)
	}

	@Test
	fun `a consumer jackson-bom version property cannot pull Jackson below the floor`() {
		val consumer = ConsumerFixture(directory, "spring-app")
		consumer.appendToBuildScript("extra[\"jackson-bom.version\"] = \"3.1.5\"")

		val jackson = insight(consumer, "jackson-databind", "runtimeClasspath")

		assertTrue(jackson.contains("tools.jackson.core:jackson-databind:${canon("jacksonBom")}"), jackson)
	}

	@Test
	fun `the catalog jOOQ version is the one the platform BOM manages`() {
		val consumer = ConsumerFixture(directory, "spring-app")
		consumer.appendToBuildScript("dependencies { implementation(\"org.jooq:jooq\") }")

		val jooq = insight(consumer, "org.jooq:jooq", "runtimeClasspath")

		assertTrue(jooq.contains("org.jooq:jooq:${canon("jooq")}"), jooq)
	}

	private fun insight(
		consumer: ConsumerFixture,
		dependency: String,
		configuration: String,
	): String =
		consumer
			.runner("dependencyInsight", "--dependency", dependency, "--configuration", configuration)
			.build()
			.output

	private fun canon(name: String): String = System.getProperty("platform.canon.$name")
}
