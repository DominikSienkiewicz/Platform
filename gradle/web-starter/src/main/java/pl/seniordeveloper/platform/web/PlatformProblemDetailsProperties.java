package pl.seniordeveloper.platform.web;

import org.springframework.boot.context.properties.ConfigurationProperties;

/** Przełączniki kontraktu błędów RFC 9457 ({@link PlatformProblemDetailsExceptionHandler}). */
@ConfigurationProperties(prefix = "platform.web.problem-details")
public class PlatformProblemDetailsProperties {

  /** Maps exceptions to application/problem+json; off hands the errors back to Spring Boot. */
  private boolean enabled = true;

  /**
   * Copies detail into a top-level message member for clients that read message; on throughout the
   * 1.x line.
   */
  private boolean legacyMessage = true;

  /** Tworzy przełączniki z wartościami domyślnymi: oba włączone. */
  public PlatformProblemDetailsProperties() {}

  /**
   * Czy starter mapuje wyjątki na {@code application/problem+json}.
   *
   * @return {@code true}, gdy kontrakt błędów działa; domyślnie {@code true}
   */
  public boolean isEnabled() {
    return enabled;
  }

  /**
   * Ustawia, czy starter mapuje wyjątki na {@code application/problem+json}.
   *
   * @param enabled {@code false} oddaje obsługę błędów Spring Bootowi
   */
  public void setEnabled(boolean enabled) {
    this.enabled = enabled;
  }

  /**
   * Czy odpowiedź kopiuje {@code detail} do pola {@code message} najwyższego poziomu.
   *
   * @return {@code true}, gdy pole jest obecne; domyślnie {@code true} w całej linii 1.x
   */
  public boolean isLegacyMessage() {
    return legacyMessage;
  }

  /**
   * Ustawia, czy odpowiedź kopiuje {@code detail} do pola {@code message} najwyższego poziomu.
   *
   * @param legacyMessage {@code false} usuwa pole, gdy żaden klient już go nie czyta
   */
  public void setLegacyMessage(boolean legacyMessage) {
    this.legacyMessage = legacyMessage;
  }
}
