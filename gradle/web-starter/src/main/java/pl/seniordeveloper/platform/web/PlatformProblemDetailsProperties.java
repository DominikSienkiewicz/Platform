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

  public boolean isEnabled() {
    return enabled;
  }

  public void setEnabled(boolean enabled) {
    this.enabled = enabled;
  }

  public boolean isLegacyMessage() {
    return legacyMessage;
  }

  public void setLegacyMessage(boolean legacyMessage) {
    this.legacyMessage = legacyMessage;
  }
}
