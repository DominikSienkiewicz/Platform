plugins {
	`java-library`
	id("seniordev.java-conventions")
	id("seniordev.quality-conventions")
}

group = "example"
version = "0.1.0-SNAPSHOT"

// Baseline JUnit z seniordev.java-conventions dubluje te linie, ale pin z gradle.properties go jeszcze nie niesie,
// a na tym pinie budują starter backend-ci-smoke i scripts/new-consumer.sh. Usuń je, gdy pin dojdzie do wydania z baseline.
dependencies {
	testImplementation(platform(libs.junit.bom))
	testImplementation("org.junit.jupiter:junit-jupiter")
	testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}
