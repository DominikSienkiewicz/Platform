package pl.seniordeveloper.platform.testing;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;

/**
 * Reguły guarda Flyway na czystych listach ścieżek, bez classpath: złe nazwy także w podkatalogach
 * (Flyway skanuje rekurencyjnie) i zduplikowane wersje, także między rootami main i test.
 */
class FlywayMigrationViolationsTest {

  @Test
  void wellNamedVersionedAndRepeatableMigrationsPass() {
    assertThat(violations(Map.of("main", List.of("V1__a.sql", "V1_1__b.sql", "R__c.sql")))).isEmpty();
  }

  @Test
  void aBadlyNamedMigrationIsReportedByName() {
    assertThat(violations(Map.of("main", List.of("V1__a.sql", "V2_init.sql"))))
        .singleElement(org.assertj.core.api.InstanceOfAssertFactories.STRING)
        .contains("V2_init.sql");
  }

  @Test
  void duplicateVersionsAreReportedWhateverTheSeparator() {
    assertThat(violations(Map.of("main", List.of("V3__a.sql", "V3__b.sql"))))
        .singleElement(org.assertj.core.api.InstanceOfAssertFactories.STRING)
        .contains("duplicate version 3");
    assertThat(violations(Map.of("main", List.of("V1.1__a.sql", "V1_1__b.sql"))))
        .singleElement(org.assertj.core.api.InstanceOfAssertFactories.STRING)
        .contains("duplicate version 1.1");
  }

  @Test
  void migrationsInSubdirectoriesAreChecked() {
    assertThat(violations(Map.of("main", List.of("V1__a.sql", "sub/V5__ok.sql")))).isEmpty();
    assertThat(violations(Map.of("main", List.of("V1__a.sql", "sub/V4_x.sql"))))
        .singleElement(org.assertj.core.api.InstanceOfAssertFactories.STRING)
        .contains("sub/V4_x.sql");
  }

  @Test
  void everyRootIsChecked() {
    var roots = new LinkedHashMap<String, List<String>>();
    roots.put("main", List.of("V1__a.sql"));
    roots.put("test", List.of("V1__b.sql"));
    assertThat(violations(roots))
        .singleElement(org.assertj.core.api.InstanceOfAssertFactories.STRING)
        .contains("duplicate version 1")
        .contains("main")
        .contains("test");
  }

  private static List<String> violations(Map<String, List<String>> roots) {
    return AbstractFlywayMigrationTest.violations(roots);
  }
}
