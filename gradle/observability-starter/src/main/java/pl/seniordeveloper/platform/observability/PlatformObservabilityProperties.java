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

  /** Tworzy przełączniki z wartościami domyślnymi: wszystkie wyłączone. */
  public PlatformObservabilityProperties() {}

  /**
   * Czy starter wystawia {@code /actuator/prometheus}.
   *
   * @return {@code true}, gdy endpoint jest wystawiony; domyślnie {@code false}
   */
  public boolean isPrometheus() {
    return prometheus;
  }

  /**
   * Ustawia, czy starter wystawia {@code /actuator/prometheus}.
   *
   * @param prometheus {@code true} wystawia endpoint
   */
  public void setPrometheus(boolean prometheus) {
    this.prometheus = prometheus;
  }

  /**
   * Czy security starter przepuszcza {@code /actuator/prometheus} bez uwierzytelnienia.
   *
   * @return {@code true}, gdy metryki są publiczne; domyślnie {@code false}
   */
  public boolean isPublicMetrics() {
    return publicMetrics;
  }

  /**
   * Ustawia, czy security starter przepuszcza {@code /actuator/prometheus} bez uwierzytelnienia.
   *
   * @param publicMetrics {@code true} dla scrapera w sieci wewnętrznej; działa tylko razem z {@link
   *     #setPrometheus(boolean) prometheus}
   */
  public void setPublicMetrics(boolean publicMetrics) {
    this.publicMetrics = publicMetrics;
  }

  /**
   * Czy logi konsoli wychodzą jako ECS JSON.
   *
   * @return {@code true}, gdy logi są w JSON-ie; domyślnie {@code false}
   */
  public boolean isJsonLogs() {
    return jsonLogs;
  }

  /**
   * Ustawia, czy logi konsoli wychodzą jako ECS JSON.
   *
   * @param jsonLogs {@code true} ustawia {@code logging.structured.format.console=ecs}
   */
  public void setJsonLogs(boolean jsonLogs) {
    this.jsonLogs = jsonLogs;
  }
}
