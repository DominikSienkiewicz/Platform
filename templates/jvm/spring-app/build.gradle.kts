plugins {
	alias(libs.plugins.spring.boot)
	id("seniordev.java-conventions")
	id("seniordev.quality-conventions")
	id("seniordev.spring-modulith-conventions")
}

group = "example"
version = "0.1.0-SNAPSHOT"

dependencies {
	implementation(libs.boot.starter.webmvc)
	implementation(libs.modulith.starter.core)
}
