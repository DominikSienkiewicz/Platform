package pl.seniordeveloper.platform.testing;

import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Bean;
import org.testcontainers.ollama.OllamaContainer;
import org.testcontainers.utility.DockerImageName;

/**
 * Opcjonalna konfiguracja Testcontainers dla Ollamy (local-first AI — np. Attestate). Wymaga, by
 * konsument miał na classpath {@code org.testcontainers:testcontainers-ollama} (w fixtures jest
 * {@code compileOnly}, żeby nie obciążać repo, które Ollamy nie używają).
 *
 * <p>Użycie: {@code @Import({PlatformPostgresContainer.class, PlatformOllamaContainer.class})}.
 */
@TestConfiguration(proxyBeanMethods = false)
public class PlatformOllamaContainer {

  @Bean
  @ServiceConnection
  public OllamaContainer ollamaContainer() {
    return new OllamaContainer(DockerImageName.parse(PlatformImages.OLLAMA));
  }
}
