package pl.seniordeveloper.gradle

import com.google.googlejavaformat.java.Formatter
import java.io.File
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir

/**
 * Kod sformatowany przez google-java-format (wersja z katalogu, ta sama co w Spotless konsumenta) musi
 * przechodzić platform-checkstyle bez naruszeń — inaczej spotlessApply i checkstyleMain grają w ping-ponga.
 * Korpus (`formatter-corpus/FormatterCorpus.java`) zbiera konstrukcje, przy których obie reguły mogą się
 * rozjechać: puste bloki (lambda, case, catch, typ anonimowy, rekord), switch z `yield`, text block, `var`,
 * typ przecięcia i adnotacje pól. Do tego ścieżkowe wyłączenia z checkstyle-suppressions.xml.
 */
class PlatformFormatterCheckstyleTest {

	@TempDir
	lateinit var tempDir: File

	@Test
	fun `google-java-format output of the corpus passes platform-checkstyle`() {
		val source = checkNotNull(javaClass.classLoader.getResource("formatter-corpus/FormatterCorpus.java")).readText()
		val formatted = File(tempDir, "src/main/java/pl/seniordeveloper/gradle/fixture/FormatterCorpus.java").apply {
			parentFile.mkdirs()
			writeText(Formatter().formatSource(source))
		}

		val violations = CheckstyleAudit.violations(tempDir, listOf(formatted))

		assertTrue(
			violations.isEmpty(),
			"platform-checkstyle rejects google-java-format output:\n${CheckstyleAudit.describe(violations)}\n--- formatted ---\n${formatted.readText()}",
		)
	}

	@Test
	fun `a lower-case static final field is a constant name violation only outside src-test`() {
		val holder = "package x;\n\nclass RuleHolder {\n  static final Object rule = null;\n\n  int size() {\n    return 0;\n  }\n}\n"
		val inTest = source("src/test/java/x/RuleHolder.java", holder)
		val inMain = source("src/main/java/x/RuleHolder.java", holder)

		assertEquals(emptyList<String>(), checks(inTest), "ConstantName is suppressed in src/test")
		assertEquals(listOf("ConstantNameCheck"), checks(inMain), "ConstantName stays a rule in src/main")
	}

	@Test
	fun `an Application class with only main is not a utility class`() {
		val body = { name: String -> "package x;\n\npublic class $name {\n  public static void main(String[] args) {}\n}\n" }
		val application = source("src/main/java/x/FooApplication.java", body("FooApplication"))
		val helper = source("src/main/java/x/FooHelper.java", body("FooHelper"))

		assertEquals(emptyList<String>(), checks(application), "*Application classes keep their default constructor")
		assertEquals(listOf("HideUtilityClassConstructorCheck"), checks(helper), "the rule stays active for other classes")
	}

	private fun source(path: String, content: String): File =
		File(tempDir, path).apply {
			parentFile.mkdirs()
			writeText(content)
		}

	private fun checks(file: File): List<String> =
		CheckstyleAudit.violations(File(tempDir, "audit-${file.nameWithoutExtension}-${file.parentFile.parentFile.parentFile.name}"), listOf(file))
			.map { it.sourceName.substringAfterLast('.') }
}
