package pl.seniordeveloper.platform.testing;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.net.URL;
import java.net.URLClassLoader;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;

/**
 * Kontrakt nazw z {@code deploy.yml}: przypadki z {@code liquibase-fixtures/naming-*}, każdy na
 * własnym classloaderze bez rodzica, jak w {@link LiquibaseMasterChangelogTest}.
 */
class LiquibaseDeployNamingTest {

  private static final String MASTER = "db/changelog/db.changelog-master.yaml";

  @Test
  void numberedChangesetsTheMasterIncludesPass() {
    assertThatCode(() -> verify("naming-ok")).doesNotThrowAnyException();
    assertThatCode(() -> verify("include-ok")).doesNotThrowAnyException();
  }

  @Test
  void aChangelogWithoutAChangesDirectoryPasses() {
    assertThatCode(() -> verify("empty-list")).doesNotThrowAnyException();
  }

  @Test
  void aFileOutsideTheNamingSchemeFailsWithTheCommandThatCreatesOne() {
    assertThatThrownBy(() -> verify("naming-bad-name"))
        .isInstanceOf(AssertionError.class)
        .hasMessageContaining(
            "deploy.yml tags the migrate image with the highest four-digit prefix in db/changelog/changes/")
        .hasMessageContaining(
            "db/changelog/changes/2-Add_Index.yaml: the name does not match NNNN-<slug>.yaml")
        .hasMessageContaining("scripts/bump-version.sh db new-migration <slug>")
        .hasMessageNotContaining("0001-baseline.yaml");
  }

  @Test
  void aDuplicatePrefixFailsNamingBothFiles() {
    assertThatThrownBy(() -> verify("naming-duplicate-prefix"))
        .isInstanceOf(AssertionError.class)
        .hasMessageContaining(
            "db/changelog/changes/0001-baseline.yaml: the prefix 0001 is already used by"
                + " 0001-add-index.yaml; give it the next free number");
  }

  @Test
  void aFileTheMasterDoesNotIncludeFailsAsAnOrphan() {
    assertThatThrownBy(() -> verify("naming-orphan"))
        .isInstanceOf(AssertionError.class)
        .hasMessageContaining(
            "db/changelog/changes/0002-add-index.yaml: no changeset from this file reaches"
                + " classpath:/"
                + MASTER
                + ", so Liquibase never applies it; include it in the master")
        .hasMessageNotContaining("0001-baseline.yaml:");
  }

  private static void verify(String fixture) throws Exception {
    URL root = LiquibaseDeployNamingTest.class.getResource("/liquibase-fixtures/" + fixture + "/");
    assertThat(root).as("fixture " + fixture).isNotNull();
    try (var loader = new URLClassLoader(new URL[] {Path.of(root.toURI()).toUri().toURL()}, null)) {
      AbstractLiquibaseChangelogTest.verifyDeployNaming(MASTER, loader);
    }
  }
}
