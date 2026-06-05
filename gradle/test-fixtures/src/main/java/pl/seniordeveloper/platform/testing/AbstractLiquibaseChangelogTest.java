package pl.seniordeveloper.platform.testing;

import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * Wspólny strażnik master changeloga Liquibase. Spring Boot auto-uruchamia migracje z
 * {@code classpath:/db/changelog/db.changelog-master.yaml} przy każdym starcie kontekstu — brak
 * tego pliku czyni start niedeterministycznym. Test jest Docker-free (szybki, bez tagu integration).
 *
 * <p>Konsument: {@code class LiquibaseChangelogTest extends AbstractLiquibaseChangelogTest {}}.
 * JUnit wykrywa odziedziczone {@code @Test} w podklasie konsumenta.
 */
public abstract class AbstractLiquibaseChangelogTest {

  private static final String MASTER_CHANGELOG = "/db/changelog/db.changelog-master.yaml";

  // protected (nie package-private), by podklasa konsumenta w innym pakiecie odziedziczyła @Test.
  @Test
  @DisplayName("Master changelog Liquibase istnieje na classpath i ma poprawny root")
  protected void masterChangelogExists() throws Exception {
    var resource = getClass().getResource(MASTER_CHANGELOG);
    assertNotNull(
        resource,
        "Brak classpath:" + MASTER_CHANGELOG + " — Liquibase jest na classpath, więc bez master"
            + " changelogu start aplikacji jest niedeterministyczny.");

    String content = Files.readString(Path.of(resource.toURI()));
    assertTrue(
        content.contains("databaseChangeLog"),
        "master changelog musi definiować element 'databaseChangeLog'.");
  }
}
