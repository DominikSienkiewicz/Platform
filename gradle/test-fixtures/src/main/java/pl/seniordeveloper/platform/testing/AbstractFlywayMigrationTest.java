package pl.seniordeveloper.platform.testing;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.io.IOException;
import java.math.BigInteger;
import java.net.URI;
import java.net.URISyntaxException;
import java.net.URL;
import java.nio.file.FileSystem;
import java.nio.file.FileSystemAlreadyExistsException;
import java.nio.file.FileSystems;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Collectors;
import java.util.stream.Stream;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * Wspólny strażnik migracji Flyway — analog {@link AbstractLiquibaseChangelogTest} dla repo na
 * Flyway (np. Azimuth). Spring Boot auto-uruchamia migracje z {@code classpath:/db/migration} przy
 * każdym starcie kontekstu; pusty albo źle nazwany katalog = migracje CICHO się nie wykonują, a
 * start aplikacji staje się niedeterministyczny. Test jest Docker-free (szybki, bez tagu
 * integration).
 *
 * <p>Zakres skanu jak u Flyway: KAŻDY root {@code db/migration} na classpath (main i test, także w
 * jarach), rekurencyjnie z podkatalogami. Zgłasza plik {@code .sql} o nazwie, której Flyway nie
 * rozpozna, i dwie migracje z tą samą wersją ({@code V3__a} + {@code V3__b}, {@code V1.1} + {@code
 * V1_1}) — typowy skutek równoległych gałęzi, który inaczej wychodzi dopiero w teście na Dockerze.
 *
 * <p>Konsument: {@code class FlywayMigrationTest extends AbstractFlywayMigrationTest {}}. JUnit
 * wykrywa odziedziczony {@code @Test} w podklasie konsumenta.
 */
public abstract class AbstractFlywayMigrationTest {

  private static final String MIGRATIONS_DIR = "db/migration";

  // Flyway: V<wersja>__<opis>.sql (versioned) lub R__<opis>.sql (repeatable). Separator = podwójny
  // '_'.
  // Package-private: FlywayNamePatternTest sprawdza wzorzec wprost, bez katalogu migracji na
  // classpath. Dzierżawcze *+: segment wersji nigdy nie pasuje do "__", więc cofanie niczego nie
  // zmienia, a zachłanne * przepełniało stos przy długiej wersji.
  static final Pattern FLYWAY_NAME = Pattern.compile("^(V\\d+(?:[._]\\d+)*+__|R__).+\\.sql$");

  private static final Pattern VERSION = Pattern.compile("^V(\\d+(?:[._]\\d+)*+)__");

  // protected (nie package-private), by podklasa konsumenta w innym pakiecie odziedziczyła @Test.
  @Test
  @DisplayName("Every Flyway migration root holds well-named migrations with unique versions")
  protected void migrationsExistAndAreWellNamed() throws IOException, URISyntaxException {
    var roots = migrationRoots(getClass().getClassLoader());
    assertFalse(
        roots.isEmpty(),
        "Missing classpath:/"
            + MIGRATIONS_DIR
            + " — Flyway is on the classpath, so without migrations"
            + " the application start is not deterministic.");
    assertTrue(
        roots.values().stream().anyMatch(paths -> !paths.isEmpty()),
        "classpath:/" + MIGRATIONS_DIR + " holds no .sql migration.");
    var violations = violations(roots);
    assertTrue(violations.isEmpty(), "Flyway migrations:\n  " + String.join("\n  ", violations));
  }

  /**
   * Naruszenia dla mapy root → ścieżki plików {@code .sql} względem roota (z podkatalogami).
   * Package-private: FlywayMigrationViolationsTest sprawdza reguły bez classpath.
   */
  static List<String> violations(Map<String, List<String>> relativePathsByRoot) {
    var violations = new ArrayList<String>();
    var byVersion = new TreeMap<String, List<String>>();
    relativePathsByRoot.forEach(
        (root, paths) ->
            paths.forEach(
                path -> {
                  var name = path.substring(path.lastIndexOf('/') + 1);
                  if (!FLYWAY_NAME.matcher(name).matches()) {
                    violations.add(
                        path
                            + " in "
                            + root
                            + " is not a Flyway name (V<version>__<description>.sql or R__<description>.sql)");
                    return;
                  }
                  Matcher version = VERSION.matcher(name);
                  if (version.find()) {
                    byVersion
                        .computeIfAbsent(normalized(version.group(1)), key -> new ArrayList<>())
                        .add(path + " in " + root);
                  }
                }));
    byVersion.forEach(
        (version, migrations) -> {
          if (migrations.size() > 1) {
            violations.add("duplicate version " + version + ": " + String.join(", ", migrations));
          }
        });
    return violations;
  }

  // Flyway porównuje wersje liczbowo i traktuje '.' i '_' tak samo: V1_01 == V1.1.
  private static String normalized(String version) {
    return Stream.of(version.split("[._]"))
        .map(part -> new BigInteger(part).toString())
        .collect(Collectors.joining("."));
  }

  // Package-private: FlywayMigrationRootsTest sprawdza roots z katalogu i z jara.
  static Map<String, List<String>> migrationRoots(ClassLoader loader)
      throws IOException, URISyntaxException {
    var roots = new LinkedHashMap<String, List<String>>();
    for (URL url : Collections.list(loader.getResources(MIGRATIONS_DIR))) {
      URI uri = url.toURI();
      if (!"jar".equals(uri.getScheme())) {
        roots.put(uri.toString(), sqlFiles(Path.of(uri)));
        continue;
      }
      // Migracje spakowane w jar: własny system plików zamykamy, cudzy, już otwarty, zostawiamy
      // właścicielowi.
      FileSystem jar;
      boolean opened = true;
      try {
        jar = FileSystems.newFileSystem(uri, Map.of());
      } catch (FileSystemAlreadyExistsException _) {
        jar = FileSystems.getFileSystem(uri);
        opened = false;
      }
      try {
        roots.put(uri.toString(), sqlFiles(jar.provider().getPath(uri)));
      } finally {
        if (opened) {
          jar.close();
        }
      }
    }
    return roots;
  }

  private static List<String> sqlFiles(Path root) throws IOException {
    try (var files = Files.walk(root)) {
      return files
          .filter(Files::isRegularFile)
          .filter(file -> file.getFileName().toString().endsWith(".sql"))
          .map(file -> root.relativize(file).toString().replace('\\', '/'))
          .sorted()
          .toList();
    }
  }
}
