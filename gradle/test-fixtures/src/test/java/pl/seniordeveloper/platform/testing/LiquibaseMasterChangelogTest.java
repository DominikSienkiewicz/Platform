package pl.seniordeveloper.platform.testing;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.net.URL;
import java.net.URLClassLoader;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;

/**
 * Master changelog sprawdzany parserem Liquibase, bez bazy. Każdy przypadek dostaje własny
 * classloader z katalogu {@code liquibase-fixtures/<przypadek>}, bez rodzica, więc nie widzi
 * changelogu testów.
 */
class LiquibaseMasterChangelogTest {

  private static final String MASTER = "db/changelog/db.changelog-master.yaml";

  @Test
  void anIncludeOfAnExistingFilePasses() {
    assertThatCode(() -> verify("include-ok")).doesNotThrowAnyException();
  }

  @Test
  void anIncludeOfAMissingFileFailsNamingIt() {
    assertThatThrownBy(() -> verify("include-missing"))
        .isInstanceOf(AssertionError.class)
        .hasMessageContaining("0002-missing.yaml");
  }

  @Test
  void aMasterWithDatabaseChangeLogOnlyInACommentFails() {
    assertThatThrownBy(() -> verify("comment-only")).isInstanceOf(AssertionError.class);
  }

  @Test
  void anInvalidYamlMasterFails() {
    assertThatThrownBy(() -> verify("invalid-yaml")).isInstanceOf(AssertionError.class);
  }

  @Test
  void anEmptyChangeLogListPasses() {
    assertThatCode(() -> verify("empty-list")).doesNotThrowAnyException();
  }

  @Test
  void aMissingMasterFailsNamingTheExpectedLocation() {
    assertThatThrownBy(() -> verify("no-master"))
        .isInstanceOf(AssertionError.class)
        .hasMessageContaining(MASTER);
  }

  private static void verify(String fixture) throws Exception {
    URL root =
        LiquibaseMasterChangelogTest.class.getResource("/liquibase-fixtures/" + fixture + "/");
    assertThat(root).as("fixture " + fixture).isNotNull();
    try (var loader = new URLClassLoader(new URL[] {Path.of(root.toURI()).toUri().toURL()}, null)) {
      AbstractLiquibaseChangelogTest.verifyMasterChangelog(MASTER, loader);
    }
  }
}
