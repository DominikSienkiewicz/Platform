package pl.seniordeveloper.platform.testing;

/**
 * Nazwy tagów JUnit, na których seniordev.spring-modulith-conventions dzieli testy (ADR-0009):
 * {@value #INTEGRATION} trafia do {@code integrationTest}, a {@value #MODEL} do {@code modelTest}.
 * Zamiast gołych stringów używaj {@link IntegrationTest}, {@link ModelTest} albo {@link
 * PostgresIntegrationTest}.
 */
public final class PlatformTestTags {

  /** Testy z Testcontainers albo pełnym kontekstem; poza szybkim zadaniem {@code test}. */
  public static final String INTEGRATION = "integration";

  /** Testy modelu (np. reguły domeny na większych danych); poza {@code test} i {@code check}. */
  public static final String MODEL = "model";

  /**
   * Test w kwarantannie (N-REL-13): biegnie w {@code quarantineTest} poza {@code check}, a {@code
   * platformQuarantineCheck} wymaga obok komentarza {@code // quarantine: <issue> until
   * YYYY-MM-DD}.
   */
  public static final String QUARANTINE = "quarantine";

  private PlatformTestTags() {}
}
