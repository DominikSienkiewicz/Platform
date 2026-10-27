package pl.seniordeveloper.platform.testing.schema.jdbc;

import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.context.TestPropertySource;
import pl.seniordeveloper.platform.testing.AbstractEventPublicationRegistryIT;
import pl.seniordeveloper.platform.testing.PlatformPostgresDatabasePerContext;
import pl.seniordeveloper.platform.testing.schema.SchemaTemplates;

/**
 * {@link AbstractEventPublicationRegistryIT} tak, jak użyje go konsument: aplikacja z {@code
 * spring-modulith-starter-jdbc} w tym samym pakiecie, migracje Flyway z kanonicznego szablonu,
 * własna baza kontekstu. Liquibase jest na classpath tylko dla {@link
 * ModulithJdbcEventPublicationSchemaIT}.
 */
@PlatformPostgresDatabasePerContext
@TestPropertySource(properties = "spring.liquibase.enabled=false")
class SampleEventPublicationRegistryIT extends AbstractEventPublicationRegistryIT {

  // Jeden katalog na klasę: flywayLocation() przy każdym wywołaniu kopiuje szablon do nowego
  // katalogu.
  private static final String FLYWAY_LOCATION = SchemaTemplates.flywayLocation();

  @DynamicPropertySource
  static void flywayTemplate(DynamicPropertyRegistry registry) {
    registry.add("spring.flyway.locations", () -> FLYWAY_LOCATION);
  }
}
