import net.ltgt.gradle.errorprone.CheckSeverity
import net.ltgt.gradle.errorprone.errorprone
import pl.seniordeveloper.gradle.PlatformVersions

/*
 * seniordev.nullness-conventions (opt-in, N-CAP-11)
 * ------------------------------------------------
 * Error Prone z NullAway w trybie JSpecify: kompilacja main failuje na dereferencji wartości @Nullable — ale tylko
 * w pakietach oznaczonych @NullMarked (OnlyNullMarked), więc adopcja idzie pakiet po pakiecie (np. jeden moduł
 * Modulith przez package-info.java). Pozostałe reguły Error Prone zostają w domyślnej wadze; ich ostrzeżenia są
 * ostrzeżeniami javac, więc zapadka platform.javac.werror z java-conventions zamienia w błędy także je.
 *
 * Osobny plugin, nie część java-conventions: Error Prone wpina się w wewnętrzne API javac i bywa w tyle za nowym
 * JDK, więc nie może blokować bumpu toolchainu u konsumentów, którzy go nie używają. Testy (compileTestJava) mają
 * NullAway wyłączony; kod generowany (build/generated) jest wykluczony.
 * Error Prone i NullAway to narzędzia, nie zależności biznesowe (zasada 2); wersje z gradle/catalog (PlatformVersions).
 */

plugins {
	java
	id("net.ltgt.errorprone")
}

dependencies {
	"errorprone"("com.google.errorprone:error_prone_core:${PlatformVersions.ERROR_PRONE}")
	"errorprone"("com.uber.nullaway:nullaway:${PlatformVersions.NULLAWAY}")
}

tasks.withType<JavaCompile>().configureEach {
	val main = name == "compileJava"
	options.errorprone {
		disableWarningsInGeneratedCode.set(true)
		excludedPaths.set(".*/build/generated/.*")
		check("NullAway", if (main) CheckSeverity.ERROR else CheckSeverity.OFF)
		option("NullAway:OnlyNullMarked", "true")
		option("NullAway:JSpecifyMode", "true")
	}
}
