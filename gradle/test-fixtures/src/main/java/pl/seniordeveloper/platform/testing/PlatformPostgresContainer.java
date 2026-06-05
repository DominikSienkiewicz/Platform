package pl.seniordeveloper.platform.testing;

import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Bean;
import org.testcontainers.postgresql.PostgreSQLContainer;
import org.testcontainers.utility.DockerImageName;

/**
 * Współdzielona konfiguracja Testcontainers: dokładnie JEDEN PostgreSQL+pgvector z
 * {@link ServiceConnection}. Obraz przypięty centralnie ({@link PlatformImages#PGVECTOR}) —
 * koniec rozjazdu tagów między repo.
 *
 * <p>Użycie: {@code @Import(PlatformPostgresContainer.class)} lub
 * {@code SpringApplication.from(App::main).with(PlatformPostgresContainer.class)}.
 */
@TestConfiguration(proxyBeanMethods = false)
public class PlatformPostgresContainer {

  // Uwaga: zmodularyzowany org.testcontainers.postgresql.PostgreSQLContainer jest NIE-generyczny
  // (brak <SELF>), więc używamy typu surowego — z <?>/<> kod się nie kompiluje.
  @Bean
  @ServiceConnection
  @SuppressWarnings({"rawtypes", "unchecked"})
  public PostgreSQLContainer pgvectorContainer() {
    return new PostgreSQLContainer(
        DockerImageName.parse(PlatformImages.PGVECTOR).asCompatibleSubstituteFor("postgres"));
  }
}
