package pl.seniordeveloper.platform.testing;

import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.io.File;
import java.util.regex.Pattern;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * Wspólny strażnik migracji Flyway — analog {@link AbstractLiquibaseChangelogTest} dla repo na
 * Flyway (np. Azimuth). Spring Boot auto-uruchamia migracje z {@code classpath:/db/migration} przy
 * każdym starcie kontekstu; pusty albo źle nazwany katalog = migracje CICHO się nie wykonują, a
 * start aplikacji staje się niedeterministyczny. Test jest Docker-free (szybki, bez tagu
 * integration).
 *
 * <p>Konsument: {@code class FlywayMigrationTest extends AbstractFlywayMigrationTest {}}. JUnit
 * wykrywa odziedziczony {@code @Test} w podklasie konsumenta.
 */
public abstract class AbstractFlywayMigrationTest {

  private static final String MIGRATIONS_DIR = "/db/migration";

  // Flyway: V<wersja>__<opis>.sql (versioned) lub R__<opis>.sql (repeatable). Separator = podwójny '_'.
  private static final Pattern FLYWAY_NAME = Pattern.compile("^(V\\d+(?:[._]\\d+)*__|R__).+\\.sql$");

  // protected (nie package-private), by podklasa konsumenta w innym pakiecie odziedziczyła @Test.
  @Test
  @DisplayName("Katalog migracji Flyway istnieje na classpath i zawiera poprawnie nazwane migracje")
  protected void migrationsExistAndAreWellNamed() throws Exception {
    var resource = getClass().getResource(MIGRATIONS_DIR);
    assertNotNull(
        resource,
        "Brak classpath:" + MIGRATIONS_DIR + " — Flyway jest na classpath, więc bez migracji start"
            + " aplikacji jest niedeterministyczny.");

    File dir = new File(resource.toURI());
    File[] sql = dir.listFiles((d, name) -> name.endsWith(".sql"));
    assertNotNull(sql, "Nie udało się odczytać katalogu migracji: " + dir);
    assertTrue(
        sql.length > 0, "Katalog " + MIGRATIONS_DIR + " nie zawiera żadnej migracji .sql.");

    for (File f : sql) {
      assertTrue(
          FLYWAY_NAME.matcher(f.getName()).matches(),
          "Plik migracji '"
              + f.getName()
              + "' łamie konwencję Flyway (V<n>__opis.sql lub R__opis.sql).");
    }
  }
}
