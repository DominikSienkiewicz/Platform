package pl.seniordeveloper.gradle

import org.gradle.api.Project
import org.sonarqube.gradle.SonarExtension

/**
 * Ustawienia całej analizy SonarQube Cloud w korzeniu hierarchii (F-13, zasada 8): host, organizacja i projectKey
 * raz, w projekcie, który zaaplikował org.sonarqube, a `sonar` czeka na raport JaCoCo każdego projektu. Woła je
 * seniordev.quality-conventions w jednomodułowym roocie i seniordev.sonar-conventions w wielomodułowym.
 */
object PlatformSonar {
	private const val CONFIGURED = "platformSonarConfigured"

	fun configureAnalysis(
		project: Project,
		settings: PlatformExtension,
	) {
		val extra = project.extensions.extraProperties
		if (extra.has(CONFIGURED)) return
		extra.set(CONFIGURED, true)
		val projectKey =
			settings.sonar.projectKey
				.orElse(project.providers.gradleProperty("sonarProjectKey"))
				.orElse("DominikSienkiewicz_${project.rootProject.name}")
		project.extensions.configure(SonarExtension::class.java) {
			properties {
				property("sonar.host.url", "https://sonarcloud.io")
				property("sonar.organization", "dominiksienkiewicz")
				property("sonar.projectKey", projectKey.get())
			}
		}
		// `sonar` czyta ŚWIEŻE raporty pokrycia (JaCoCo z java-conventions) wszystkich projektów; nazwy tasków
		// rozwiązuje dopiero graf, gdy każdy projekt jest już skonfigurowany.
		project.tasks.named("sonar") {
			dependsOn(project.provider { project.allprojects.mapNotNull { it.tasks.findByName("jacocoTestReport") } })
		}
	}
}
