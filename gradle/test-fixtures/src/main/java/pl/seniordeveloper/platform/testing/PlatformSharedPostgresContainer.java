package pl.seniordeveloper.platform.testing;

import java.util.Map;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.test.context.DynamicPropertyRegistrar;
import org.testcontainers.postgresql.PostgreSQLContainer;
import org.testcontainers.utility.DockerImageName;

/**
 * Jeden PostgreSQL z pgvector na całą JVM, wspólny dla wszystkich kontekstów Springa w cache
 * testów. {@link PlatformPostgresContainer} jest beanem per kontekst, więc każda odrębna sygnatura
 * kontekstu startuje własny kontener — u konsumenta 19 sygnatur dało 20 kontenerów i OOM runnera
 * CI.
 *
 * <p>Kontener celowo NIE jest beanem: Spring Boot zamyka kontener-bean przy zamknięciu kontekstu
 * (także z {@code destroyMethod = ""}), a cache kontekstów zamyka je przy wyrzucaniu, więc wspólny
 * kontener padłby pod kontekstami, które jeszcze go używają. Startuje leniwie przy pierwszym
 * kontekście, połączenie trafia do {@code spring.datasource.*} przez {@link
 * DynamicPropertyRegistrar} (działa w testach i w {@code
 * SpringApplication.from(App::main).with(...)}), a sprząta go Ryuk przy końcu JVM.
 *
 * <p>Działa bez trwałości: {@code fsync}, {@code synchronous_commit} i {@code full_page_writes}
 * wyłączone, dane na tmpfs — bezpieczne wyłącznie dlatego, że to kontener Testcontainers (nigdy w
 * {@code infra/docker-compose.yml}). Z {@code testcontainers.reuse.enable=true} w {@code
 * ~/.testcontainers.properties} kontener przeżywa też kolejne uruchomienia lokalne; CI tego nie
 * ustawia.
 *
 * <p>Konteksty dzielą bazę: test, który zakładał świeżą bazę, musi sprzątać po sobie albo używać
 * własnego schematu. Drugi kontekst uruchamia migracje na zmigrowanej już bazie, co zwykle nic nie
 * robi. Własną bazę dla każdego kontekstu na tym samym serwerze daje {@link
 * PlatformPostgresDatabasePerContext}.
 *
 * <p>Użycie: {@code @Import(PlatformSharedPostgresContainer.class)}; adres i poświadczenia daje
 * {@link #container()}.
 */
@TestConfiguration(proxyBeanMethods = false)
public class PlatformSharedPostgresContainer {

  private static final class Holder {
    static final PostgreSQLContainer CONTAINER = start(create());

    private static PostgreSQLContainer start(PostgreSQLContainer container) {
      container.start();
      return container;
    }
  }

  /**
   * Wspólny kontener tej JVM, uruchamiany przy pierwszym wywołaniu.
   *
   * @return działający kontener, ten sam dla każdego kontekstu
   */
  public static PostgreSQLContainer container() {
    return Holder.CONTAINER;
  }

  // Kontener żyje do końca JVM (sprząta go Ryuk), więc nie ma tu close(); zwracamy tę samą
  // instancję, którą konfigurują metody with*.
  static PostgreSQLContainer create() {
    var container =
        new PostgreSQLContainer(
            DockerImageName.parse(PlatformImages.PGVECTOR).asCompatibleSubstituteFor("postgres"));
    container
        .withCommand(
            "postgres",
            "-c",
            "fsync=off",
            "-c",
            "synchronous_commit=off",
            "-c",
            "full_page_writes=off")
        // Obrazy PostgreSQL 18 trzymają PGDATA w /var/lib/postgresql/18/docker, pod tym punktem
        // montowania.
        .withTmpFs(Map.of("/var/lib/postgresql", "rw"))
        .withReuse(true);
    return container;
  }

  /**
   * Kieruje {@code spring.datasource.*} kontekstu na wspólny kontener.
   *
   * @return rejestrator właściwości połączenia
   */
  @Bean
  public DynamicPropertyRegistrar platformSharedPostgresProperties() {
    PlatformTestTaskGuard.requireIntegrationTask("PlatformSharedPostgresContainer");
    return registry -> {
      PostgreSQLContainer postgres = container();
      registry.add("spring.datasource.url", postgres::getJdbcUrl);
      registry.add("spring.datasource.username", postgres::getUsername);
      registry.add("spring.datasource.password", postgres::getPassword);
    };
  }
}
