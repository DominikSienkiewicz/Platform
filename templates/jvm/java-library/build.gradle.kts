plugins {
	`java-library`
	id("seniordev.java-conventions")
	id("seniordev.quality-conventions")
}

group = "example"
version = "0.1.0-SNAPSHOT"

// JUnit (BOM, Jupiter, launcher) dokłada seniordev.java-conventions; tu tylko zależności biblioteki.
