package pl.seniordeveloper.platform.testing;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

class FlywayNamePatternTest {

  @ParameterizedTest
  @ValueSource(strings = {"V1__init.sql", "V1_1__add_index.sql", "V1.1__add_index.sql", "R__view.sql"})
  void acceptsVersionedAndRepeatableMigrations(String name) {
    assertTrue(AbstractFlywayMigrationTest.FLYWAY_NAME.matcher(name).matches(), name);
  }

  @ParameterizedTest
  @ValueSource(strings = {"v1__init.sql", "V1_init.sql", "V__init.sql", "init.sql", "V1__init.txt"})
  void rejectsNamesFlywayWouldSkip(String name) {
    assertFalse(AbstractFlywayMigrationTest.FLYWAY_NAME.matcher(name).matches(), name);
  }
}
