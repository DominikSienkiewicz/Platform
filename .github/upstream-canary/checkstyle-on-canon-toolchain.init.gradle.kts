// Init script nogi next-jdk w upstream-canary.yml: Checkstyle na toolchainie kanonu, reszta startera na następnym JDK.
//
// Gradle odtwarza WorkParameters workera procesowego przez ReflectionFactory.newConstructorForSerialization, które
// JDK 28-ea+24 domyślnie odrzuca (gradle/gradle#39837). Task Checkstyle nie ma jvmArgs, a worker nie dziedziczy
// JAVA_TOOL_OPTIONS, więc flagi -Djdk.reflect.allowNonSerializableConstruction=true nie da się podać. Checkstyle czyta
// źródła, nie bajtkod, więc JVM jego workera nie zmienia tego, co noga mierzy.
// Zdejmij ten plik i jego użycie w upstream-canary.yml, gdy wrapper Gradle kanonu będzie miał poprawkę
// gradle/gradle#39837. Pilnuje templates/tests/upstream-canary-checkstyle-toolchain.test.sh.
val canaryCheckstyleJava =
	providers.gradleProperty("canaryCheckstyleJava").orNull?.trim()?.toInt()
		?: error("checkstyle-on-canon-toolchain.init.gradle.kts needs -PcanaryCheckstyleJava=<the Java version of the canon>")

allprojects {
	pluginManager.withPlugin("checkstyle") {
		val launcher =
			extensions.getByType<JavaToolchainService>().launcherFor {
				languageVersion.set(JavaLanguageVersion.of(canaryCheckstyleJava))
			}
		tasks.withType<Checkstyle>().configureEach {
			javaLauncher.set(launcher)
		}
	}
}
