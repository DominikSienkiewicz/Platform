package pl.seniordeveloper.platform.observability;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Przełączniki startera observability. Czyta je {@link
 * PlatformObservabilityEnvironmentPostProcessor} przed startem kontekstu, bo od nich zależą
 * domyślne wartości {@code management.*}; klasa daje też metadane IDE.
 */
@ConfigurationProperties(prefix = "platform.observability")
public class PlatformObservabilityProperties {

  /** Exposes /actuator/prometheus; off by default, because metrics leak information. */
  private boolean prometheus = false;

  /**
   * Lets the security starter serve /actuator/prometheus without authentication, for a scraper
   * inside the network; needs prometheus=true.
   */
  private boolean publicMetrics = false;

  /** Writes console logs as ECS JSON (logging.structured.format.console=ecs). */
  private boolean jsonLogs = false;

  public boolean isPrometheus() {
    return prometheus;
  }

  public void setPrometheus(boolean prometheus) {
    this.prometheus = prometheus;
  }

  public boolean isPublicMetrics() {
    return publicMetrics;
  }

  public void setPublicMetrics(boolean publicMetrics) {
    this.publicMetrics = publicMetrics;
  }

  public boolean isJsonLogs() {
    return jsonLogs;
  }

  public void setJsonLogs(boolean jsonLogs) {
    this.jsonLogs = jsonLogs;
  }
}
