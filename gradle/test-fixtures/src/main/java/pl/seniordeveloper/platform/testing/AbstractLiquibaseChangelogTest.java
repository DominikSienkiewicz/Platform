package pl.seniordeveloper.platform.testing;

import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.fail;

import liquibase.changelog.ChangeLogParameters;
import liquibase.exception.LiquibaseException;
import liquibase.parser.ChangeLogParserFactory;
import liquibase.resource.ClassLoaderResourceAccessor;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * Wspólny strażnik master changeloga Liquibase. Spring Boot auto-uruchamia migracje z {@code
 * classpath:/db/changelog/db.changelog-master.yaml} przy każdym starcie kontekstu — brak tego pliku
 * czyni start niedeterministycznym. Test jest Docker-free (szybki, bez tagu integration).
 *
 * <p>Master jest parsowany parserem Liquibase bez bazy, więc literówka w ścieżce {@code include},
 * brakujący plik, niepoprawny YAML albo {@code databaseChangeLog} tylko w komentarzu failują tutaj,
 * a nie dopiero w teście kontekstu na Testcontainers. Zasoby czyta classloader, więc działa też
 * changelog spakowany w jar. Konsument musi mieć {@code org.liquibase:liquibase-core} na classpath
 * testów — ma go każde repo na Liquibase.
 *
 * <p>Konsument: {@code class LiquibaseChangelogTest extends AbstractLiquibaseChangelogTest {}}.
 * JUnit wykrywa odziedziczone {@code @Test} w podklasie konsumenta.
 */
public abstract class AbstractLiquibaseChangelogTest {

  private static final String MASTER_CHANGELOG = "db/changelog/db.changelog-master.yaml";

  // protected (nie package-private), by podklasa konsumenta w innym pakiecie odziedziczyła @Test.
  @Test
  @DisplayName(
      "The Liquibase master changelog exists on the classpath and parses with its includes")
  protected void masterChangelogExists() throws Exception {
    verifyMasterChangelog(MASTER_CHANGELOG, getClass().getClassLoader());
  }

  // Package-private: LiquibaseMasterChangelogTest sprawdza przypadki na własnych classloaderach.
  static void verifyMasterChangelog(String location, ClassLoader loader) throws Exception {
    assertNotNull(
        loader.getResource(location),
        "Missing classpath:/"
            + location
            + " — Liquibase is on the classpath, so without a master changelog the application"
            + " start is not deterministic.");
    try (var accessor = new ClassLoaderResourceAccessor(loader)) {
      var changeLog =
          ChangeLogParserFactory.getInstance()
              .getParser(location, accessor)
              .parse(location, new ChangeLogParameters(), accessor);
      assertNotNull(changeLog, "Liquibase parsed no changelog from classpath:/" + location);
    } catch (LiquibaseException | RuntimeException e) {
      fail(
          "The Liquibase master changelog classpath:/"
              + location
              + " does not parse: "
              + e.getMessage(),
          e);
    }
  }
}
