package pl.seniordeveloper.gradle

import org.gradle.api.Action
import org.gradle.api.Project
import org.gradle.api.model.ObjectFactory
import org.gradle.api.provider.ListProperty
import org.gradle.api.provider.Property
import java.math.BigDecimal
import javax.inject.Inject

/**
 * Typowane pokrętła konwencji Platform — blok `platform { }` w skrypcie builda konsumenta (N-DX-15).
 *
 * Każde pole jest opcjonalne. Nieustawione bierze właściwość Gradle'a nazwaną w jego opisie, więc build
 * skonfigurowany przez `gradle.properties` albo `-P` działa dalej, podobnie jak nadpisanie w CI. Pole jest
 * czytane przy konfiguracji jego taska; ustawienie go później failuje, zamiast przejść bez skutku.
 *
 * ```kotlin
 * platform {
 *     coverage { minimum.set("0.80".toBigDecimal()) }
 *     mutation { targetPackages.add("pl.example.orders") }
 * }
 * ```
 */
abstract class PlatformExtension
	@Inject
	constructor(
		objects: ObjectFactory,
	) {
		/** Bramka pokrycia JaCoCo w `check` (`seniordev.java-conventions`). */
		val coverage: Coverage = objects.newInstance(Coverage::class.java)

		/** Analiza SonarQube Cloud (`seniordev.quality-conventions`, `seniordev.sonar-conventions`). */
		val sonar: Sonar = objects.newInstance(Sonar::class.java)

		/** Testy mutacyjne PIT (`seniordev.quality-conventions`). */
		val mutation: Mutation = objects.newInstance(Mutation::class.java)

		/** SpotBugs (`seniordev.quality-conventions`). */
		val staticAnalysis: StaticAnalysis = objects.newInstance(StaticAnalysis::class.java)

		fun coverage(action: Action<in Coverage>) = action.execute(coverage)

		fun sonar(action: Action<in Sonar>) = action.execute(sonar)

		fun mutation(action: Action<in Mutation>) = action.execute(mutation)

		fun staticAnalysis(action: Action<in StaticAnalysis>) = action.execute(staticAnalysis)

		abstract class Coverage {
			/**
			 * Minimalne pokrycie instrukcji `test` i `integrationTest` łącznie, ułamek 0..1. Nieustawione: właściwość
			 * `coverageMinimum`, potem 0.00. Wartość spoza 0..1 failuje z PLAT-COV-002.
			 */
			abstract val minimum: Property<BigDecimal>
		}

		abstract class Sonar {
			/** Klucz projektu SonarQube Cloud. Nieustawiony: właściwość `sonarProjectKey`, potem `DominikSienkiewicz_<rootProject.name>`. */
			abstract val projectKey: Property<String>
		}

		abstract class Mutation {
			/** Pakiety, które mutuje PIT, każdy z podpakietami. Nieustawione: domyślne PIT-a, klasy `<group>.*`. */
			abstract val targetPackages: ListProperty<String>

			/**
			 * Minimalna siła mutacji PIT, ułamek 0..1, zaokrąglany w górę do pełnego procentu. Nieustawione: właściwość
			 * `platform.mutation.threshold`, potem bez progu (domyślne PIT-a). Wartość spoza 0..1 failuje z PLAT-MUT-001.
			 */
			abstract val threshold: Property<BigDecimal>
		}

		abstract class StaticAnalysis {
			/** `true`: znaleziska SpotBugs failują build. Nieustawione: `false`, tylko raport (ADR-0005). */
			abstract val failOnBugs: Property<Boolean>
		}

		companion object {
			const val NAME = "platform"

			/** Rozszerzenie [project], rejestrowane przez tę konwencję Platform, która zadziała pierwsza. */
			fun of(project: Project): PlatformExtension =
				project.extensions.findByType(PlatformExtension::class.java)
					?: project.extensions.create(NAME, PlatformExtension::class.java)
		}
	}
