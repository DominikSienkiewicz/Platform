package pl.seniordeveloper.gradle

import java.io.File
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

/**
 * Górny wiersz docs/compatibility.md opisuje main: bump javy, BOM-u, Gradle albo kanonu frontendu bez
 * aktualizacji tabeli wywala ten test. Starsze wiersze to historia i nic ich nie sprawdza.
 */
class CompatibilityMatrixTest {

	private val topRow: Map<String, String> = topRow(File(System.getProperty("platform.compatibilityDoc")).readText())

	@Test
	fun `the top row matches the catalog`() {
		assertEquals(
			mapOf(
				"Java toolchain" to canon("java"),
				"Gradle tested" to canon("gradle"),
				"Spring Boot" to canon("springBoot"),
				"Spring Modulith" to canon("springModulith"),
				"Spring AI" to canon("springAi"),
			),
			topRow.filterKeys { it in setOf("Java toolchain", "Gradle tested", "Spring Boot", "Spring Modulith", "Spring AI") },
		)
	}

	@Test
	fun `the top row names the runtime image of the Dockerfile template`() {
		val dockerfile = File(System.getProperty("platform.dockerfileTemplate")).readText()
		assertEquals(RuntimeImage.finalStage(dockerfile)?.reference, topRow["Runtime image"])
	}

	@Test
	fun `the top row matches the Gradle minimum and the JDK backend-ci runs Gradle on`() {
		assertEquals(System.getProperty("platform.minimumConsumerGradle"), topRow["Gradle minimum"])
		val backendCi = File(System.getProperty("platform.workflows"), "backend-ci.yml").readText()
		val gradleJdk = Regex("""\n {6}java-version:\n(?: {8}.*\n)*? {8}default: "([^"]+)"""").find(backendCi)?.groupValues?.get(1)
		assertEquals(gradleJdk, topRow["JDK running Gradle"])
	}

	@Test
	fun `the top row matches the frontend canon and workspace`() {
		val manifest = File(System.getProperty("platform.frontendManifest")).readText()
		val canon = File(System.getProperty("platform.frontendCanon")).readText()
		assertEquals(Regex(""""node":\s*"([^"]+)"""").find(manifest)?.groupValues?.get(1), topRow["Node"])
		assertEquals(Regex(""""packageManager":\s*"pnpm@([^"]+)"""").find(manifest)?.groupValues?.get(1), topRow["pnpm (Platform)"])
		assertEquals(Regex(""""next":\s*"([^"]+)"""").find(canon)?.groupValues?.get(1), topRow["Next.js"])
	}

	private fun canon(name: String): String = System.getProperty("platform.canon.$name")

	private fun topRow(document: String): Map<String, String> {
		val lines = document.lines().dropWhile { it.trim() != "<!-- compatibility-matrix -->" }.drop(1)
		check(lines.size >= 3) { "docs/compatibility.md lacks the table after <!-- compatibility-matrix -->" }
		val header = cells(lines[0])
		val row = cells(lines[2]).map { it.replace("`", "").removeSuffix("¹").trim() }
		check(header.size == row.size) { "the top row of docs/compatibility.md has ${row.size} cells, the header ${header.size}" }
		return header.zip(row).toMap()
	}

	private fun cells(line: String): List<String> = line.trim().removePrefix("|").removeSuffix("|").split("|").map { it.trim() }
}
