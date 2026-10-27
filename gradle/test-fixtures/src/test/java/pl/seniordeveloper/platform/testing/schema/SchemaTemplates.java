package pl.seniordeveloper.platform.testing.schema;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.file.Files;
import java.nio.file.Path;

/**
 * Kanoniczne migracje z {@code templates/db/}, czytane z repozytorium, a nie z kopii w zasobach
 * testu. Publiczna, bo korzystają z niej też testy rejestru JDBC z osobnego source setu {@code
 * jdbcRegistryTest}.
 */
public final class SchemaTemplates {

  // Ścieżkę ustawia build.gradle.kts, który deklaruje też katalog jako wejście tasków test i
  // jdbcRegistryTest.
  private static final String TEMPLATES_PROPERTY = "platform.templates.dir";

  private SchemaTemplates() {}

  public static String liquibaseChangeLog() {
    return "file:" + template("db/liquibase/modulith-event-publication.yaml");
  }

  /**
   * Flyway wymaga numeru wersji w nazwie, więc szablon {@code V__…} trafia do katalogu jako {@code
   * V1__…}.
   */
  public static String flywayLocation() {
    try {
      Path location = Files.createTempDirectory("platform-flyway-");
      Files.copy(
          template("db/flyway/V__modulith_event_publication.sql"),
          location.resolve("V1__modulith_event_publication.sql"));
      return "filesystem:" + location;
    } catch (IOException e) {
      throw new UncheckedIOException(e);
    }
  }

  private static Path template(String relative) {
    String templates = System.getProperty(TEMPLATES_PROPERTY);
    if (templates == null) {
      throw new IllegalStateException(
          "System property " + TEMPLATES_PROPERTY + " is not set; run the test through Gradle");
    }
    Path template = Path.of(templates, relative).toAbsolutePath().normalize();
    if (!Files.isRegularFile(template)) {
      throw new IllegalStateException("Missing template " + template);
    }
    return template;
  }
}
