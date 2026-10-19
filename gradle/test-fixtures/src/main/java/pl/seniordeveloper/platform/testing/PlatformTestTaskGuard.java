package pl.seniordeveloper.platform.testing;

/**
 * Kontener Testcontainers w szybkim zadaniu {@code test} to nieotagowany test integracyjny: wymaga
 * Dockera tam, gdzie go nie ma, a {@code integrationTest} nic nie uruchamia. Zadanie Gradle podaje
 * swoją nazwę we właściwości {@value #TASK_PROPERTY}; bez niej strażnik milczy.
 */
final class PlatformTestTaskGuard {

  static final String TASK_PROPERTY = "platform.test.task";

  private PlatformTestTaskGuard() {}

  static void requireIntegrationTask(String container) {
    if ("test".equals(System.getProperty(TASK_PROPERTY))) {
      throw new IllegalStateException(
          "Testcontainers used in the unit 'test' task ("
              + container
              + "): annotate the test class with @IntegrationTest or @PostgresIntegrationTest");
    }
  }
}
