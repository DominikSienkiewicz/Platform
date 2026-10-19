package pl.seniordeveloper.platform.testing;

import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.core.env.Environment;

/**
 * Migracje kontra encje na prawdziwym PostgreSQL: kontekst startuje na {@link
 * PlatformSharedPostgresContainer} z {@code spring.jpa.hibernate.ddl-auto=validate}, więc najpierw
 * biegnie Liquibase albo Flyway, a potem Hibernate porównuje każdą encję z powstałym schematem —
 * także {@code JpaEventPublication} Spring Moduliths, któremu bez tabeli {@code event_publication}
 * rejestr zdarzeń po cichu nie zapisuje publikacji. Brak tabeli albo kolumny wywala start kontekstu
 * komunikatem Hibernate'a, np. {@code missing table [event_publication]}; kanoniczna migracja jest
 * w {@code templates/db/}.
 *
 * <p>Konsument: {@code class SchemaValidationIT extends AbstractSchemaValidationIT {}} w pakiecie
 * aplikacji (albo poniżej), żeby {@code @SpringBootTest} znalazł jej
 * {@code @SpringBootConfiguration}. Kolumnę, której typu Hibernate nie umie porównać (np. pgvector
 * bez {@code hibernate-vector}), wyłącza się z walidacji filtrem tabel {@code
 * spring.jpa.properties.hibernate.hbm2ddl.schema_filter_provider} w {@code @TestPropertySource}
 * podklasy — z komentarzem, dlaczego.
 */
@IntegrationTest
@SpringBootTest(properties = "spring.jpa.hibernate.ddl-auto=validate")
@Import(PlatformSharedPostgresContainer.class)
public abstract class AbstractSchemaValidationIT {

  @Autowired private Environment environment;

  // protected (nie package-private), by podklasa konsumenta w innym pakiecie odziedziczyła @Test.
  @Test
  @DisplayName(
      "The migrations create the schema every JPA entity expects, Spring Modulith's included")
  protected void migrationsMatchTheEntities() {
    assertEquals(
        "validate",
        environment.getProperty("spring.jpa.hibernate.ddl-auto"),
        "spring.jpa.hibernate.ddl-auto is overridden for this test, so Hibernate did not compare the"
            + " entities with the migrated schema");
  }
}
