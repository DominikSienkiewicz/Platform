package pl.seniordeveloper.platform.testing;

import java.lang.annotation.Documented;
import java.lang.annotation.ElementType;
import java.lang.annotation.Inherited;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;
import org.springframework.context.annotation.Import;

/**
 * Własna baza danych dla każdego kontekstu Springa na wspólnym serwerze z {@link
 * PlatformSharedPostgresContainer}. Bez niej konteksty dzielą jedną bazę, więc dwie sygnatury
 * kontekstu widzą nawzajem swoje tabele. Z nią każdy kontekst wykonuje przy starcie {@code CREATE
 * DATABASE ctx_<n>} i dostaje jej adres, użytkownika i hasło w {@code spring.datasource.*}, a
 * serwer zostaje jednym kontenerem na JVM. Zamknięcie kontekstu (wyrzucenie z cache albo koniec
 * JVM) kasuje jego bazę.
 *
 * <p>Izoluje sygnatury kontekstu, nie klasy testów: klasy z tą samą konfiguracją dzielą kontekst z
 * cache, a z nim bazę. Migracje biegną od zera w każdym kontekście.
 *
 * <p>Obok {@link PostgresIntegrationTest} albo na klasie konfiguracji, którą startuje {@code
 * SpringApplicationBuilder}:
 *
 * <pre>{@code
 * @PostgresIntegrationTest
 * @PlatformPostgresDatabasePerContext
 * class OrderRepositoryIT {}
 * }</pre>
 *
 * <p>Importuje {@link PlatformSharedPostgresContainer} przed rejestratorem bazy kontekstu, a z
 * dwóch rejestracji tej samej właściwości wygrywa późniejsza, więc {@code spring.datasource.*}
 * wskazuje bazę kontekstu. Kontekst, w którym coś zarejestrowało {@code spring.datasource.url}
 * później (np. {@link PlatformSharedPostgresContainer} podany jako źródło aplikacji zamiast przez
 * {@code Import}), nie startuje i nazywa przyczynę.
 */
@Target(ElementType.TYPE)
@Retention(RetentionPolicy.RUNTIME)
@Documented
@Inherited
@Import({PlatformSharedPostgresContainer.class, PostgresDatabasePerContextRegistrar.class})
public @interface PlatformPostgresDatabasePerContext {}
