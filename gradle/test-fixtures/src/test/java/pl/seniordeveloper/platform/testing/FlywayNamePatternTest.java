package pl.seniordeveloper.platform.testing;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

class FlywayNamePatternTest {

  @ParameterizedTest
  @ValueSource(
      strings = {"V1__init.sql", "V1_1__add_index.sql", "V1.1__add_index.sql", "R__view.sql"})
  void acceptsVersionedAndRepeatableMigrations(String name) {
    assertTrue(AbstractFlywayMigrationTest.FLYWAY_NAME.matcher(name).matches(), name);
  }

  @ParameterizedTest
  @ValueSource(strings = {"v1__init.sql", "V1_init.sql", "V__init.sql", "init.sql", "V1__init.txt"})
  void rejectsNamesFlywayWouldSkip(String name) {
    assertFalse(AbstractFlywayMigrationTest.FLYWAY_NAME.matcher(name).matches(), name);
  }

  // Zachłanne powtórzenie grupy (?:[._]\d+)* cofa się rekurencyjnie po każdym segmencie wersji,
  // więc długa wersja przepełniała stos (Sonar java:S5998); dzierżawcze *+ dopasowuje iteracyjnie.
  @Test
  void checksAVersionWithManySegmentsWithoutOverflowingTheStack() {
    String name = "V1" + "_1".repeat(100_000) + "__long_version.sql";

    assertEquals(
        List.of(), AbstractFlywayMigrationTest.violations(Map.of("db/migration", List.of(name))));
  }
}
