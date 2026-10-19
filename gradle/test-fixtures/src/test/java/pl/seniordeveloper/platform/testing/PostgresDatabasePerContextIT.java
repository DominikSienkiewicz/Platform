package pl.seniordeveloper.platform.testing;

import static org.assertj.core.api.Assertions.assertThat;
import static org.junit.jupiter.api.Assumptions.assumeTrue;

import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.springframework.boot.SpringBootConfiguration;
import org.springframework.boot.WebApplicationType;
import org.springframework.boot.autoconfigure.ImportAutoConfiguration;
import org.springframework.boot.builder.SpringApplicationBuilder;
import org.springframework.boot.jdbc.autoconfigure.DataSourceAutoConfiguration;
import org.springframework.boot.jdbc.autoconfigure.JdbcTemplateAutoConfiguration;
import org.springframework.boot.testcontainers.properties.TestcontainersPropertySourceAutoConfiguration;
import org.springframework.context.ConfigurableApplicationContext;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;
import org.testcontainers.DockerClientFactory;

@IntegrationTest
class PostgresDatabasePerContextIT {

  private static final String TABLE = "created_in_the_first_context";

  @BeforeAll
  static void requireDocker() {
    assumeTrue(DockerClientFactory.instance().isDockerAvailable(), "Docker is not available");
  }

  @Test
  void twoDifferentContextsGetTheirOwnDatabaseOnTheSameServer() {
    try (ConfigurableApplicationContext first = start(FirstApplication.class);
        ConfigurableApplicationContext second = start(SecondApplication.class)) {
      assertThat(systemIdentifier(second)).isEqualTo(systemIdentifier(first));
      assertThat(AbstractTestcontainersFootprintTest.postgresContainersOfThisSession()).hasSize(1);

      String sharedDatabase = PlatformSharedPostgresContainer.container().getDatabaseName();
      String firstDatabase = currentDatabase(first);
      String secondDatabase = currentDatabase(second);
      assertThat(firstDatabase)
          .startsWith("ctx_")
          .isNotEqualTo(secondDatabase)
          .isNotEqualTo(sharedDatabase);
      assertThat(secondDatabase).startsWith("ctx_").isNotEqualTo(sharedDatabase);

      jdbc(first).execute("CREATE TABLE " + TABLE + " (id integer)");
      assertThat(tableExists(first)).isTrue();
      assertThat(tableExists(second)).isFalse();
    }
  }

  @Test
  void aContextWithoutTheOptInKeepsTheSharedDatabase() {
    try (ConfigurableApplicationContext own = start(FirstApplication.class);
        ConfigurableApplicationContext shared = start(SharedApplication.class)) {
      assertThat(currentDatabase(shared))
          .isEqualTo(PlatformSharedPostgresContainer.container().getDatabaseName());
      assertThat(systemIdentifier(shared)).isEqualTo(systemIdentifier(own));

      jdbc(own).execute("CREATE TABLE " + TABLE + " (id integer)");
      assertThat(tableExists(shared)).isFalse();
    }
  }

  @Test
  void closingAContextDropsItsDatabaseAndKeepsTheOthers() {
    try (ConfigurableApplicationContext survivor = start(SecondApplication.class)) {
      String closed;
      try (ConfigurableApplicationContext first = start(FirstApplication.class)) {
        closed = currentDatabase(first);
      }

      assertThat(databaseExists(survivor, closed)).isFalse();
      assertThat(databaseExists(survivor, currentDatabase(survivor))).isTrue();
    }
  }

  private static ConfigurableApplicationContext start(Class<?> application) {
    return new SpringApplicationBuilder(application)
        .web(WebApplicationType.NONE)
        .properties("spring.main.banner-mode=off")
        .run();
  }

  private static JdbcTemplate jdbc(ConfigurableApplicationContext context) {
    return context.getBean(JdbcTemplate.class);
  }

  private static String currentDatabase(ConfigurableApplicationContext context) {
    String database = jdbc(context).queryForObject("SELECT current_database()", String.class);
    assertThat(database).isNotNull();
    return database;
  }

  private static long systemIdentifier(ConfigurableApplicationContext context) {
    Long identifier =
        jdbc(context)
            .queryForObject("SELECT system_identifier FROM pg_control_system()", Long.class);
    assertThat(identifier).isNotNull();
    return identifier;
  }

  private static boolean tableExists(ConfigurableApplicationContext context) {
    return Boolean.TRUE.equals(
        jdbc(context).queryForObject("SELECT to_regclass(?) IS NOT NULL", Boolean.class, TABLE));
  }

  private static boolean databaseExists(ConfigurableApplicationContext context, String database) {
    return Boolean.TRUE.equals(
        jdbc(context)
            .queryForObject(
                "SELECT EXISTS (SELECT 1 FROM pg_database WHERE datname = ?)",
                Boolean.class,
                database));
  }

  @SpringBootConfiguration(proxyBeanMethods = false)
  // Tylko JDBC: JPA, Modulith, Liquibase i Flyway z classpath testów nie zakładają nic w bazach.
  @ImportAutoConfiguration({
    TestcontainersPropertySourceAutoConfiguration.class,
    DataSourceAutoConfiguration.class,
    JdbcTemplateAutoConfiguration.class
  })
  // Jak @PostgresIntegrationTest obok opt-inu: wspólny kontener zaimportowany także wprost.
  @Import(PlatformSharedPostgresContainer.class)
  @PlatformPostgresDatabasePerContext
  static class FirstApplication {}

  @SpringBootConfiguration(proxyBeanMethods = false)
  @ImportAutoConfiguration({
    TestcontainersPropertySourceAutoConfiguration.class,
    DataSourceAutoConfiguration.class,
    JdbcTemplateAutoConfiguration.class
  })
  @PlatformPostgresDatabasePerContext
  static class SecondApplication {

    @Bean
    String secondContextMarker() {
      return "a different context signature";
    }
  }

  @SpringBootConfiguration(proxyBeanMethods = false)
  @ImportAutoConfiguration({
    TestcontainersPropertySourceAutoConfiguration.class,
    DataSourceAutoConfiguration.class,
    JdbcTemplateAutoConfiguration.class
  })
  @Import(PlatformSharedPostgresContainer.class)
  static class SharedApplication {}
}
