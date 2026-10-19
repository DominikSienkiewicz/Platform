package pl.seniordeveloper.platform.testing;

/**
 * Kontener Testcontainers w szybkim zadaniu {@code test} to nieotagowany test integracyjny: wymaga
 * Dockera tam, gdzie go nie ma, a {@code integrationTest} nic nie uruchamia. Zadanie Gradle podaje
 * swoją nazwę we właściwości {@value #TASK_PROPERTY}; bez niej strażnik milczy.
 *
 * <p>Wdrożenie w dwóch krokach: najpierw ostrzeżenie na stderr, a {@value #MODE_PROPERTY}{@code
 * =fail} (domyślne w kolejnym wydaniu MINOR) zamienia je w {@link IllegalStateException}.
 */
final class PlatformTestTaskGuard {

  static final String TASK_PROPERTY = "platform.test.task";
  static final String MODE_PROPERTY = "platform.test.guard";

  private PlatformTestTaskGuard() {}

  static void requireIntegrationTask(String container) {
    if (!"test".equals(System.getProperty(TASK_PROPERTY))) {
      return;
    }
    String message =
        "Testcontainers used in the unit 'test' task ("
            + container
            + "): annotate the test class with @IntegrationTest or @PostgresIntegrationTest";
    if ("fail".equals(System.getProperty(MODE_PROPERTY))) {
      throw new IllegalStateException(message);
    }
    System.err.println("WARNING: " + message + ". A later Platform release fails such a test.");
  }
}
