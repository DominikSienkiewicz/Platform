package pl.seniordeveloper.platform.testing;

import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.fail;

import java.io.IOException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeSet;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import liquibase.changelog.ChangeLogParameters;
import liquibase.changelog.ChangeSet;
import liquibase.changelog.DatabaseChangeLog;
import liquibase.exception.LiquibaseException;
import liquibase.parser.ChangeLogParserFactory;
import liquibase.resource.ClassLoaderResourceAccessor;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.core.io.Resource;
import org.springframework.core.io.support.PathMatchingResourcePatternResolver;

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
 * <p>Drugi test pilnuje kontraktu z {@code deploy.yml}: tag obrazu migracji to najwyższy
 * czterocyfrowy prefiks w {@code db/changelog/changes/}, więc każdy plik tam ma nazwę {@code
 * NNNN-<slug>.yaml} (tak tworzy go {@code scripts/bump-version.sh db new-migration}), prefiksy są
 * unikalne, a master dociąga każdy plik — plik poza masterem podbiłby tag bez zmiany schematu. Bez
 * katalogu {@code changes/} test nic nie sprawdza.
 *
 * <p>Konsument: {@code class LiquibaseChangelogTest extends AbstractLiquibaseChangelogTest {}}.
 * JUnit wykrywa odziedziczone {@code @Test} w podklasie konsumenta.
 */
public abstract class AbstractLiquibaseChangelogTest {

  private static final String MASTER_CHANGELOG = "db/changelog/db.changelog-master.yaml";
  private static final String CHANGES = "db/changelog/changes/";
  private static final Pattern DEPLOY_NAME = Pattern.compile("(\\d{4})-[a-z0-9-]+\\.ya?ml");

  // protected (nie package-private), by podklasa konsumenta w innym pakiecie odziedziczyła @Test.
  @Test
  @DisplayName(
      "The Liquibase master changelog exists on the classpath and parses with its includes")
  protected void masterChangelogExists() throws Exception {
    verifyMasterChangelog(MASTER_CHANGELOG, getClass().getClassLoader());
  }

  @Test
  @DisplayName(
      "Every file in db/changelog/changes is named NNNN-<slug>.yaml with a unique prefix and reaches the"
          + " master changelog")
  protected void changesFollowTheDeployNaming() throws Exception {
    verifyDeployNaming(MASTER_CHANGELOG, getClass().getClassLoader());
  }

  // Package-private: LiquibaseMasterChangelogTest sprawdza przypadki na własnych classloaderach.
  static void verifyMasterChangelog(String location, ClassLoader loader) throws Exception {
    assertNotNull(
        loader.getResource(location),
        "Missing classpath:/"
            + location
            + " — Liquibase is on the classpath, so without a master changelog the application"
            + " start is not deterministic.");
    assertNotNull(
        parse(location, loader), "Liquibase parsed no changelog from classpath:/" + location);
  }

  // Package-private: LiquibaseDeployNamingTest sprawdza przypadki na własnych classloaderach.
  static void verifyDeployNaming(String master, ClassLoader loader) throws Exception {
    List<String> files = changeFiles(loader);
    if (files.isEmpty()) {
      return;
    }
    List<String> problems = new ArrayList<>();
    Map<String, String> fileByPrefix = new HashMap<>();
    for (String file : files) {
      Matcher name = DEPLOY_NAME.matcher(file);
      if (!name.matches()) {
        problems.add(
            CHANGES
                + file
                + ": the name does not match NNNN-<slug>.yaml (four digits, a dash, lower-case kebab"
                + " case); create changesets with scripts/bump-version.sh db new-migration <slug>");
        continue;
      }
      String earlier = fileByPrefix.putIfAbsent(name.group(1), file);
      if (earlier != null) {
        problems.add(
            CHANGES
                + file
                + ": the prefix "
                + name.group(1)
                + " is already used by "
                + earlier
                + "; give it the next free number");
      }
    }
    Set<String> included = includedChangeFiles(parse(master, loader));
    for (String file : files) {
      if (!included.contains(file)) {
        problems.add(
            CHANGES
                + file
                + ": no changeset from this file reaches classpath:/"
                + master
                + ", so Liquibase never applies it; include it in the master");
      }
    }
    if (!problems.isEmpty()) {
      fail(
          "deploy.yml tags the migrate image with the highest four-digit prefix in "
              + CHANGES
              + ", so every file there must be a numbered changeset the master applies:\n  "
              + String.join("\n  ", problems));
    }
  }

  private static List<String> changeFiles(ClassLoader loader) throws IOException {
    Set<String> names = new TreeSet<>();
    for (Resource resource :
        new PathMatchingResourcePatternResolver(loader)
            .getResources("classpath*:" + CHANGES + "*")) {
      if (resource.isReadable() && resource.getFilename() != null) {
        names.add(resource.getFilename());
      }
    }
    return List.copyOf(names);
  }

  private static Set<String> includedChangeFiles(DatabaseChangeLog changeLog) {
    Set<String> included = new TreeSet<>();
    for (ChangeSet changeSet : changeLog.getChangeSets()) {
      String path = changeSet.getFilePath().replace('\\', '/').replaceFirst("^classpath:", "");
      path = path.startsWith("/") ? path.substring(1) : path;
      if (path.startsWith(CHANGES)) {
        included.add(path.substring(CHANGES.length()));
      }
    }
    return included;
  }

  private static DatabaseChangeLog parse(String location, ClassLoader loader) throws Exception {
    try (var accessor = new ClassLoaderResourceAccessor(loader)) {
      return ChangeLogParserFactory.getInstance()
          .getParser(location, accessor)
          .parse(location, new ChangeLogParameters(), accessor);
    } catch (LiquibaseException | RuntimeException e) {
      return fail(
          "The Liquibase master changelog classpath:/"
              + location
              + " does not parse: "
              + e.getMessage(),
          e);
    }
  }
}
