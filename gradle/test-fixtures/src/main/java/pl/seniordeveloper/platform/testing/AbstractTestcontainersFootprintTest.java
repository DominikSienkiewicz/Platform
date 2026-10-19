package pl.seniordeveloper.platform.testing;

import static org.junit.jupiter.api.Assertions.assertTrue;

import com.github.dockerjava.api.model.Container;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.testcontainers.DockerClientFactory;

/**
 * Bramka śladu Testcontainers: w tej JVM działa co najwyżej {@link #maximumPostgresContainers()}
 * kontenerów PostgreSQL Platform. Kontener jako bean per kontekst mnoży się z każdą sygnaturą
 * kontekstu w cache (u konsumenta: 20 kontenerów, 7,1 GB RSS, OOM runnera) — {@link
 * PlatformSharedPostgresContainer} trzyma jeden. Uogólnienie {@code IntegrationContextFootprintIT}
 * z Azimutha.
 *
 * <p>Liczy kontenery tej sesji Testcontainers w chwili uruchomienia, więc klasa musi biec po
 * testach, które budują konteksty: {@code @Order} z {@code
 * junit.jupiter.testclass.order.default=org.junit.jupiter.api.ClassOrderer$OrderAnnotation} w
 * {@code junit-platform.properties}:
 *
 * <pre>{@code
 * @Order(Integer.MAX_VALUE)
 * class TestcontainersFootprintIT extends AbstractTestcontainersFootprintTest {}
 * }</pre>
 */
@IntegrationTest
public abstract class AbstractTestcontainersFootprintTest {

  /**
   * Ile kontenerów PostgreSQL Platform może działać naraz w tej JVM.
   *
   * @return domyślnie 1
   */
  protected int maximumPostgresContainers() {
    return 1;
  }

  // protected (nie package-private), by podklasa konsumenta w innym pakiecie odziedziczyła @Test.
  @Test
  @DisplayName("One Platform PostgreSQL container serves every Spring context of this JVM")
  protected void onePostgresContainerPerJvm() {
    List<Container> running = postgresContainersOfThisSession();
    assertTrue(
        running.size() <= maximumPostgresContainers(),
        running.size()
            + " Platform PostgreSQL containers run in this JVM, at most "
            + maximumPostgresContainers()
            + " expected: import PlatformSharedPostgresContainer instead of a container bean per context");
  }

  static List<Container> postgresContainersOfThisSession() {
    String image = PlatformImages.PGVECTOR.split(":")[0];
    return DockerClientFactory.instance()
        .client()
        .listContainersCmd()
        .withLabelFilter(
            Map.of(
                DockerClientFactory.TESTCONTAINERS_SESSION_ID_LABEL,
                DockerClientFactory.SESSION_ID))
        .exec()
        .stream()
        .filter(container -> container.getImage().startsWith(image))
        .toList();
  }
}
