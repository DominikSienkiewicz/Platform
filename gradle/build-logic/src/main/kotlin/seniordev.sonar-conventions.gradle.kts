import pl.seniordeveloper.gradle.PlatformExtension
import pl.seniordeveloper.gradle.PlatformSonar

/*
 * seniordev.sonar-conventions
 * ---------------------------
 * Korzeń wielomodułowego konsumenta (F-13): jedna analiza SonarQube Cloud zamiast osobnego `:<moduł>:sonar` w każdym
 * module z tym samym projectKey. Moduły dalej aplikują seniordev.quality-conventions i dopisują do analizy własny
 * raport JaCoCo; root dostaje jeden task `sonar`, który czeka na raporty wszystkich modułów.
 * Konsument jednomodułowy go nie potrzebuje — quality-conventions w roocie robi to samo.
 */

plugins {
	id("org.sonarqube")
}

if (project.path != ":") {
	throw GradleException(
		"seniordev.sonar-conventions belongs in the root project of the build, but ${project.path} applies it. " +
			"Apply it once in the root build.gradle.kts; the modules keep seniordev.quality-conventions.",
	)
}

PlatformSonar.configureAnalysis(project, PlatformExtension.of(project))
