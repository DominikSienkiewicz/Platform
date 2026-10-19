package pl.seniordeveloper.platform.testing;

/**
 * Kontener Testcontainers w szybkim zadaniu {@code test} to nieotagowany test integracyjny: wymaga
 * Dockera tam, gdzie go nie ma, a {@code integrationTest} nic nie uruchamia. Zadanie Gradle podaje
 * swoją nazwę we właściwości {@value #TASK_PROPERTY}; bez niej strażnik milczy.
 *
 * <p>Domyślnie strażnik rzuca {@link IllegalStateException} (faza fail z ADR-0019, po wydaniu
 * 1.6.0, które tylko ostrzegało). {@value #MODE_PROPERTY}{@code =warn} zostawia ostrzeżenie na
 * stderr dla konsumenta, który potrzebuje czasu. Każda inna niepusta wartość też rzuca, a komunikat
 * podaje, że to nie jest tryb strażnika: literówka w opt-oucie nie wyłącza go po cichu.
 */
final class PlatformTestTaskGuard {

  static final String TASK_PROPERTY = "platform.test.task";
  static final String MODE_PROPERTY = "platform.test.guard";
  static final String WARN_MODE = "warn";
  static final String FAIL_MODE = "fail";

  private PlatformTestTaskGuard() {}

  static void requireIntegrationTask(String container) {
    if (!"test".equals(System.getProperty(TASK_PROPERTY))) {
      return;
    }
    String message =
        "Testcontainers used in the unit 'test' task ("
            + container
            + "): annotate the test class with @IntegrationTest or @PostgresIntegrationTest";
    String mode = configuredMode();
    if (WARN_MODE.equals(mode)) {
      System.err.println(
          "WARNING: "
              + message
              + ". "
              + MODE_PROPERTY
              + "="
              + WARN_MODE
              + " keeps this a warning; without it the test fails.");
      return;
    }
    if (FAIL_MODE.equals(mode)) {
      throw new IllegalStateException(message);
    }
    throw new IllegalStateException(
        message
            + ". "
            + MODE_PROPERTY
            + "="
            + mode
            + " is not a guard mode: use "
            + WARN_MODE
            + " to keep a warning, or "
            + FAIL_MODE);
  }

  private static String configuredMode() {
    String mode = System.getProperty(MODE_PROPERTY);
    if (mode == null || mode.isBlank()) {
      return FAIL_MODE;
    }
    return mode.trim();
  }
}
