package pl.seniordeveloper.platform.testing;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import org.junit.jupiter.api.Test;
import org.junit.platform.commons.support.AnnotationSupport;
import org.springframework.context.annotation.Import;

class PostgresDatabasePerContextTest {

  private static final String SERVER = "jdbc:postgresql://localhost:55432/test?loggerLevel=OFF";

  private static final String OWN = "jdbc:postgresql://localhost:55432/ctx_7?loggerLevel=OFF";

  @Test
  void theOptInImportsTheSharedServerAheadOfTheRegistrarThatReplacesItsDatabase() {
    assertThat(
            AnnotationSupport.findAnnotation(
                PlatformPostgresDatabasePerContext.class, Import.class))
        .hasValueSatisfying(
            imported ->
                assertThat(imported.value())
                    .containsExactly(
                        PlatformSharedPostgresContainer.class,
                        PostgresDatabasePerContextRegistrar.class));
  }

  @Test
  void aContextDatabaseKeepsTheServerAddressAndItsParameters() {
    assertThat(PostgresDatabasePerContextRegistrar.jdbcUrl(SERVER, "ctx_7")).isEqualTo(OWN);
    assertThat(
            PostgresDatabasePerContextRegistrar.jdbcUrl(
                "jdbc:postgresql://localhost:55432/test", "ctx_7"))
        .isEqualTo("jdbc:postgresql://localhost:55432/ctx_7");
  }

  @Test
  void aLaterRegistrationOfTheUrlFailsTheContextWithTheFix() {
    assertThatCode(() -> PostgresDatabasePerContextRegistrar.requireOwnDatabase(OWN, OWN))
        .doesNotThrowAnyException();

    assertThatThrownBy(() -> PostgresDatabasePerContextRegistrar.requireOwnDatabase(OWN, SERVER))
        .isInstanceOf(IllegalStateException.class)
        .hasMessage(
            "spring.datasource.url of this context is "
                + SERVER
                + " instead of its own database "
                + OWN
                + ": something registered it after @PlatformPostgresDatabasePerContext. Import"
                + " PlatformSharedPostgresContainer through @PostgresIntegrationTest or @Import, not as"
                + " an application source");
  }
}
