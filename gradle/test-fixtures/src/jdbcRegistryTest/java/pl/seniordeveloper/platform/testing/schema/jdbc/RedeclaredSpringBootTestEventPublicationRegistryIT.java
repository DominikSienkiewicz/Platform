package pl.seniordeveloper.platform.testing.schema.jdbc;

import static org.assertj.core.api.Assertions.assertThat;
import static org.junit.jupiter.api.Assumptions.assumeTrue;

import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.core.env.Environment;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.context.TestPropertySource;
import org.testcontainers.DockerClientFactory;
import pl.seniordeveloper.platform.testing.AbstractEventPublicationRegistryIT;
import pl.seniordeveloper.platform.testing.PlatformPostgresDatabasePerContext;
import pl.seniordeveloper.platform.testing.schema.SchemaTemplates;

/**
 * Podklasa, która deklaruje własne {@code @SpringBootTest} (np. z {@code classes}), nie może zgubić
 * wyłączenia tabeli zakładanej przez rejestr: bez niego fixture przechodziłby bez migracji.
 */
@SpringBootTest(classes = JdbcRegistrySampleApplication.class)
@PlatformPostgresDatabasePerContext
@TestPropertySource(properties = "spring.liquibase.enabled=false")
class RedeclaredSpringBootTestEventPublicationRegistryIT
    extends AbstractEventPublicationRegistryIT {

  private static final String FLYWAY_LOCATION = SchemaTemplates.flywayLocation();

  @BeforeAll
  static void requireDocker() {
    assumeTrue(DockerClientFactory.instance().isDockerAvailable(), "Docker is not available");
  }

  @DynamicPropertySource
  static void flywayTemplate(DynamicPropertyRegistry registry) {
    registry.add("spring.flyway.locations", () -> FLYWAY_LOCATION);
  }

  @Test
  void theRegistryStillLeavesTheTableToTheMigrations(@Autowired Environment environment) {
    assertThat(environment.getProperty("spring.modulith.events.jdbc.schema-initialization.enabled"))
        .isEqualTo("false");
  }
}
