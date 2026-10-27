package pl.seniordeveloper.platform.testing.schema;

import static org.junit.jupiter.api.Assumptions.assumeTrue;

import org.junit.jupiter.api.BeforeAll;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.context.TestPropertySource;
import org.testcontainers.DockerClientFactory;
import pl.seniordeveloper.platform.testing.AbstractEventPublicationRegistryIT;
import pl.seniordeveloper.platform.testing.PlatformPostgresDatabasePerContext;

/**
 * {@link AbstractEventPublicationRegistryIT} z rejestrem JPA: {@link SchemaSampleApplication} z
 * szablonem Liquibase, własna baza kontekstu. Wariant JDBC jest w source secie {@code
 * jdbcRegistryTest}.
 */
@PlatformPostgresDatabasePerContext
@TestPropertySource(properties = "spring.flyway.enabled=false")
class SampleJpaEventPublicationRegistryIT extends AbstractEventPublicationRegistryIT {

  @BeforeAll
  static void requireDocker() {
    assumeTrue(DockerClientFactory.instance().isDockerAvailable(), "Docker is not available");
  }

  @DynamicPropertySource
  static void liquibaseTemplate(DynamicPropertyRegistry registry) {
    registry.add("spring.liquibase.change-log", SchemaTemplates::liquibaseChangeLog);
  }
}
