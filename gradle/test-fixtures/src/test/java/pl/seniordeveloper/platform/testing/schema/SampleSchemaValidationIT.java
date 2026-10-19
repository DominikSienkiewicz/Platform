package pl.seniordeveloper.platform.testing.schema;

import static org.junit.jupiter.api.Assumptions.assumeTrue;

import org.junit.jupiter.api.BeforeAll;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.context.TestPropertySource;
import org.testcontainers.DockerClientFactory;
import pl.seniordeveloper.platform.testing.AbstractSchemaValidationIT;

/**
 * Podklasa jak u konsumenta: {@link SchemaSampleApplication} z szablonem Liquibase na wspólnym
 * serwerze.
 */
@TestPropertySource(properties = "spring.flyway.enabled=false")
class SampleSchemaValidationIT extends AbstractSchemaValidationIT {

  @BeforeAll
  static void requireDocker() {
    assumeTrue(DockerClientFactory.instance().isDockerAvailable(), "Docker is not available");
  }

  @DynamicPropertySource
  static void liquibaseTemplate(DynamicPropertyRegistry registry) {
    registry.add("spring.liquibase.change-log", SchemaTemplates::liquibaseChangeLog);
  }
}
