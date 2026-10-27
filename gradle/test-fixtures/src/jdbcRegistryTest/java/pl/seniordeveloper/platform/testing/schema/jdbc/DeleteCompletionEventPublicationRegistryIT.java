package pl.seniordeveloper.platform.testing.schema.jdbc;

import static org.junit.jupiter.api.Assumptions.assumeTrue;

import org.junit.jupiter.api.BeforeAll;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.context.TestPropertySource;
import org.testcontainers.DockerClientFactory;
import pl.seniordeveloper.platform.testing.AbstractEventPublicationRegistryIT;
import pl.seniordeveloper.platform.testing.PlatformPostgresDatabasePerContext;
import pl.seniordeveloper.platform.testing.schema.SchemaTemplates;

/**
 * Konsument z trybem {@code DELETE}: rejestr kasuje zakończoną publikację zamiast ją oznaczać, a
 * szablony ten tryb obsługują, więc fixture nie może wymagać publikacji wśród zakończonych.
 */
@PlatformPostgresDatabasePerContext
@TestPropertySource(
    properties = {
      "spring.liquibase.enabled=false",
      "spring.modulith.events.completion-mode=delete"
    })
class DeleteCompletionEventPublicationRegistryIT extends AbstractEventPublicationRegistryIT {

  private static final String FLYWAY_LOCATION = SchemaTemplates.flywayLocation();

  @BeforeAll
  static void requireDocker() {
    assumeTrue(DockerClientFactory.instance().isDockerAvailable(), "Docker is not available");
  }

  @DynamicPropertySource
  static void flywayTemplate(DynamicPropertyRegistry registry) {
    registry.add("spring.flyway.locations", () -> FLYWAY_LOCATION);
  }
}
