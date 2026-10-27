package pl.seniordeveloper.platform.testing;

import static org.junit.jupiter.api.Assertions.assertTrue;

import java.time.Instant;
import java.util.List;
import java.util.Objects;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.modulith.events.core.EventPublicationRepository;
import org.springframework.modulith.events.core.PublicationTargetIdentifier;
import org.springframework.modulith.events.core.TargetEventPublication;
import org.springframework.test.context.TestPropertySource;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * Rejestr publikacji zdarzeń Spring Moduliths na migracjach aplikacji, na prawdziwym PostgreSQL:
 * kontekst startuje na {@link PlatformSharedPostgresContainer}, migracje (Liquibase albo Flyway)
 * zakładają schemat, a test zapisuje publikację przez {@link EventPublicationRepository}, kończy ją
 * i usuwa. Działa z oboma starterami rejestru i z każdym trybem zakończenia ({@code UPDATE}, {@code
 * DELETE}, {@code ARCHIVE}), bo sprawdza, że publikacja przestała być niezakończona, a nie że jest
 * wśród zakończonych. Każde wywołanie rejestru biegnie we własnej transakcji, jak w Modulith.
 *
 * <p>{@code spring-modulith-starter-jdbc} nie sprawdza schematu przy starcie, więc bez tego testu
 * brak tabeli {@code event_publication} albo jej kolumny wychodzi dopiero przy pierwszym zdarzeniu
 * na produkcji; przy {@code spring-modulith-starter-jpa} uzupełnia {@link
 * AbstractSchemaValidationIT} zapisem przez rejestr. Kanoniczna migracja jest w {@code
 * templates/db/}.
 *
 * <p>Konsument: {@code class EventPublicationRegistryIT extends AbstractEventPublicationRegistryIT
 * {}} w pakiecie aplikacji (albo poniżej), żeby {@code @SpringBootTest} znalazł jej
 * {@code @SpringBootConfiguration}. Tabela w schemacie innym niż domyślny: {@code
 * spring.modulith.events.jdbc.schema} i migracja uruchamiana w tym schemacie.
 *
 * <p>Rejestr JDBC Modulith 2.1 domyślnie sam zakłada tabelę przy starcie; test to wyłącza, żeby
 * sprawdzić same migracje aplikacji. Właściwość stoi w {@code @TestPropertySource}, które podklasa
 * dziedziczy także wtedy, gdy deklaruje własne {@code @SpringBootTest}. Aplikacja, której migracje
 * są właścicielem schematu, ustawia to samo w konfiguracji produkcyjnej.
 */
@IntegrationTest
@SpringBootTest
@TestPropertySource(properties = "spring.modulith.events.jdbc.schema-initialization.enabled=false")
@Import(PlatformSharedPostgresContainer.class)
public abstract class AbstractEventPublicationRegistryIT {

  private static final PublicationTargetIdentifier PROBE_LISTENER =
      PublicationTargetIdentifier.of("platform.event-publication-registry-probe");

  // protected (nie package-private), by podklasa konsumenta w innym pakiecie odziedziczyła @Test.
  // Zdarzenie-sonda to String, który serializer zdarzeń Moduliths zapisuje bez konfiguracji.
  @Test
  @DisplayName("The event publication registry stores a publication and completes it")
  protected void theRegistryStoresAndCompletesAPublication(
      @Autowired EventPublicationRepository repository,
      @Autowired PlatformTransactionManager transactionManager) {
    TransactionTemplate transaction = new TransactionTemplate(transactionManager);
    String event = "platform registry probe " + UUID.randomUUID();
    TargetEventPublication publication =
        Objects.requireNonNull(
            transaction.execute(
                status -> repository.create(TargetEventPublication.of(event, PROBE_LISTENER))));
    try {
      assertTrue(
          incomplete(repository, transaction, event).isPresent(),
          "The registry did not store the probe publication " + publication.getIdentifier());

      transaction.executeWithoutResult(
          status -> repository.markCompleted(publication, Instant.now()));

      assertTrue(
          incomplete(repository, transaction, event).isEmpty(),
          "The registry did not complete the probe publication " + publication.getIdentifier());
    } finally {
      transaction.executeWithoutResult(
          status -> repository.deletePublications(List.of(publication.getIdentifier())));
    }
  }

  private static Optional<TargetEventPublication> incomplete(
      EventPublicationRepository repository, TransactionTemplate transaction, String event) {
    return Objects.requireNonNull(
        transaction.execute(
            status ->
                repository.findIncompletePublicationsByEventAndTargetIdentifier(
                    event, PROBE_LISTENER)));
  }
}
