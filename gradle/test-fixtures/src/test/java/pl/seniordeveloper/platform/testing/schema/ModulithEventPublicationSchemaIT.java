package pl.seniordeveloper.platform.testing.schema;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.junit.jupiter.api.Assumptions.assumeTrue;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.springframework.boot.WebApplicationType;
import org.springframework.boot.builder.SpringApplicationBuilder;
import org.springframework.context.ConfigurableApplicationContext;
import org.springframework.jdbc.core.JdbcTemplate;
import org.testcontainers.DockerClientFactory;
import org.testcontainers.postgresql.PostgreSQLContainer;
import pl.seniordeveloper.platform.testing.IntegrationTest;
import pl.seniordeveloper.platform.testing.PlatformSharedPostgresContainer;

/**
 * Szablony tabeli {@code event_publication} kontra encja Spring Moduliths z katalogu Platform: bez
 * migracji {@code ddl-auto=validate} wywala start, z szablonem Liquibase albo Flyway kontekst
 * wstaje. Każdy przypadek ma własną, świeżą bazę na wspólnym serwerze.
 */
@IntegrationTest
class ModulithEventPublicationSchemaIT {

  @BeforeAll
  static void requireDocker() {
    assumeTrue(DockerClientFactory.instance().isDockerAvailable(), "Docker is not available");
  }

  @Test
  void withoutTheTableHibernateValidationFailsNamingIt() {
    assertThatThrownBy(() -> start(freshDatabase()).close())
        .rootCause()
        .hasMessageContaining("missing table [event_publication]");
  }

  @Test
  void theLiquibaseTemplateCreatesTheTableTheEntityExpects() {
    List<String> properties = freshDatabase();
    properties.add("spring.liquibase.enabled=true");
    properties.add("spring.liquibase.change-log=" + SchemaTemplates.liquibaseChangeLog());
    try (ConfigurableApplicationContext context = start(properties)) {
      assertThat(publications(context)).isZero();
    }
  }

  @Test
  void theFlywayTemplateCreatesTheTableTheEntityExpects() {
    List<String> properties = freshDatabase();
    properties.add("spring.flyway.enabled=true");
    properties.add("spring.flyway.locations=" + SchemaTemplates.flywayLocation());
    try (ConfigurableApplicationContext context = start(properties)) {
      assertThat(publications(context)).isZero();
    }
  }

  private static ConfigurableApplicationContext start(List<String> properties) {
    return new SpringApplicationBuilder(SchemaSampleApplication.class)
        .web(WebApplicationType.NONE)
        .properties(properties.toArray(String[]::new))
        .run();
  }

  private static Long publications(ConfigurableApplicationContext context) {
    return context
        .getBean(JdbcTemplate.class)
        .queryForObject("SELECT count(*) FROM event_publication", Long.class);
  }

  private static List<String> freshDatabase() {
    PostgreSQLContainer postgres = PlatformSharedPostgresContainer.container();
    String database = "schema_" + UUID.randomUUID().toString().replace("-", "");
    try (Connection connection =
            DriverManager.getConnection(
                postgres.getJdbcUrl(), postgres.getUsername(), postgres.getPassword());
        Statement statement = connection.createStatement()) {
      statement.execute("CREATE DATABASE " + database);
    } catch (SQLException e) {
      throw new IllegalStateException("Cannot create database " + database, e);
    }
    String url =
        "jdbc:postgresql://"
            + postgres.getHost()
            + ":"
            + postgres.getMappedPort(PostgreSQLContainer.POSTGRESQL_PORT)
            + "/"
            + database;
    return new ArrayList<>(
        List.of(
            "spring.main.banner-mode=off",
            "spring.datasource.url=" + url,
            "spring.datasource.username=" + postgres.getUsername(),
            "spring.datasource.password=" + postgres.getPassword(),
            "spring.jpa.hibernate.ddl-auto=validate",
            "spring.liquibase.enabled=false",
            "spring.flyway.enabled=false"));
  }
}
