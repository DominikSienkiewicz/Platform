plugins {
	`java-library`
	id("seniordev.java-conventions")
	id("seniordev.quality-conventions")
}

group = "example"
version = "0.1.0-SNAPSHOT"

dependencies {
	testImplementation(platform(libs.junit.bom))
	testImplementation("org.junit.jupiter:junit-jupiter")
	testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}
