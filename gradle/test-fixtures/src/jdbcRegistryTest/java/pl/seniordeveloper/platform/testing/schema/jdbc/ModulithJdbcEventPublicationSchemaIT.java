package pl.seniordeveloper.platform.testing.schema.jdbc;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.junit.jupiter.api.Assumptions.assumeTrue;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.sql.Statement;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.springframework.boot.WebApplicationType;
import org.springframework.boot.builder.SpringApplicationBuilder;
import org.springframework.context.ConfigurableApplicationContext;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.modulith.events.EventPublication;
import org.springframework.modulith.events.core.EventPublicationRepository;
import org.springframework.modulith.events.core.PublicationTargetIdentifier;
import org.springframework.modulith.events.core.TargetEventPublication;
import org.testcontainers.DockerClientFactory;
import org.testcontainers.postgresql.PostgreSQLContainer;
import pl.seniordeveloper.platform.testing.IntegrationTest;
import pl.seniordeveloper.platform.testing.PlatformSharedPostgresContainer;
import pl.seniordeveloper.platform.testing.schema.SchemaTemplates;

/**
 * Szablony tabeli {@code event_publication} kontra rejestr publikacji Spring Moduliths na JDBC z
 * katalogu Platform: bez migracji zapis publikacji pada na brakującej tabeli, z szablonem Liquibase
 * albo Flyway rejestr zapisuje i kończy publikację, także w schemacie innym niż domyślny. Każdy
 * przypadek ma własną, świeżą bazę na wspólnym serwerze.
 *
 * <p>Modulith 2.1 domyślnie sam zakłada tabelę przy starcie (warunek z {@code matchIfMissing}),
 * więc każdy przypadek wyłącza {@code spring.modulith.events.jdbc.schema-initialization.enabled}:
 * inaczej tabela z rejestru zasłoniłaby szablon i przypadki z migracją przechodziłyby bez niej.
 */
@IntegrationTest
class ModulithJdbcEventPublicationSchemaIT {

  private static final PublicationTargetIdentifier LISTENER =
      PublicationTargetIdentifier.of("platform.registry-probe");
  private static final String NON_DEFAULT_SCHEMA = "modulith";

  @BeforeAll
  static void requireDocker() {
    assumeTrue(DockerClientFactory.instance().isDockerAvailable(), "Docker is not available");
  }

  @Test
  void withoutTheTableTheRegistryFailsNamingIt() {
    try (ConfigurableApplicationContext context = start(freshDatabase())) {
      EventPublicationRepository repository = context.getBean(EventPublicationRepository.class);

      assertThatThrownBy(() -> repository.create(probe()))
          .rootCause()
          .hasMessageContaining("relation \"event_publication\" does not exist");
    }
  }

  @Test
  void theFlywayTemplateGivesAWorkingJdbcRegistry() {
    List<String> properties = freshDatabase();
    properties.add("spring.flyway.enabled=true");
    properties.add("spring.flyway.locations=" + SchemaTemplates.flywayLocation());
    try (ConfigurableApplicationContext context = start(properties)) {
      assertTheRegistryStoresAndCompletes(context.getBean(EventPublicationRepository.class));
    }
  }

  @Test
  void theLiquibaseTemplateGivesAWorkingJdbcRegistry() {
    List<String> properties = freshDatabase();
    properties.add("spring.liquibase.enabled=true");
    properties.add("spring.liquibase.change-log=" + SchemaTemplates.liquibaseChangeLog());
    try (ConfigurableApplicationContext context = start(properties)) {
      assertTheRegistryStoresAndCompletes(context.getBean(EventPublicationRepository.class));
    }
  }

  @Test
  void theFlywayTemplateWorksInANonDefaultSchema() {
    List<String> properties = freshDatabase();
    properties.add("spring.flyway.enabled=true");
    properties.add("spring.flyway.locations=" + SchemaTemplates.flywayLocation());
    properties.add("spring.flyway.default-schema=" + NON_DEFAULT_SCHEMA);
    properties.add("spring.flyway.schemas=" + NON_DEFAULT_SCHEMA);
    properties.add("spring.modulith.events.jdbc.schema=" + NON_DEFAULT_SCHEMA);
    try (ConfigurableApplicationContext context = start(properties)) {
      EventPublicationRepository repository = context.getBean(EventPublicationRepository.class);
      repository.create(probe());

      Long rows =
          context
              .getBean(JdbcTemplate.class)
              .queryForObject(
                  "SELECT count(*) FROM " + NON_DEFAULT_SCHEMA + ".event_publication", Long.class);

      assertThat(rows).isOne();
    }
  }

  private static void assertTheRegistryStoresAndCompletes(EventPublicationRepository repository) {
    TargetEventPublication publication = repository.create(probe());
    repository.markCompleted(publication, Instant.now());

    assertThat(repository.findCompletedPublications())
        .extracting(EventPublication::getIdentifier)
        .containsExactly(publication.getIdentifier());
  }

  private static TargetEventPublication probe() {
    return TargetEventPublication.of(new RegistryProbe(UUID.randomUUID().toString()), LISTENER);
  }

  private static ConfigurableApplicationContext start(List<String> properties) {
    return new SpringApplicationBuilder(JdbcRegistrySampleApplication.class)
        .web(WebApplicationType.NONE)
        .properties(properties.toArray(String[]::new))
        .run();
  }

  private static List<String> freshDatabase() {
    PostgreSQLContainer postgres = PlatformSharedPostgresContainer.container();
    String database = "registry_" + UUID.randomUUID().toString().replace("-", "");
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
            "spring.liquibase.enabled=false",
            "spring.flyway.enabled=false",
            "spring.modulith.events.jdbc.schema-initialization.enabled=false"));
  }

  /** Zdarzenie-sonda: rekord, który serializer zdarzeń Moduliths zapisuje bez konfiguracji. */
  record RegistryProbe(String value) {}
}
