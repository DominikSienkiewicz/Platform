package pl.seniordeveloper.platform.observability;

import java.util.LinkedHashMap;
import java.util.Map;
import org.springframework.boot.EnvironmentPostProcessor;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.context.properties.bind.Binder;
import org.springframework.core.Ordered;
import org.springframework.core.env.ConfigurableEnvironment;
import org.springframework.core.env.MapPropertySource;

/**
 * Wspólna baza observability (N-CAP-4) jako domyślne wartości o NAJNIŻSZYM priorytecie: każda
 * właściwość konsumenta wygrywa. Daje to, czego oczekują security starter i bramka deployu: sondy
 * liveness/readiness pod {@code /actuator/health/**}, {@code health} i {@code info} przez HTTP,
 * szczegóły zdrowia tylko dla uwierzytelnionych i tag {@code application} na każdej metryce.
 *
 * <p>Prometheus jest opt-in ({@code platform.observability.prometheus=true}), bo metryki to wyciek
 * informacji w repo bez security startera; {@code public-metrics=true} dopisuje {@code
 * /actuator/prometheus} do domyślnych {@code platform.security.permitted-paths}. Biegnie po {@code
 * ConfigDataEnvironmentPostProcessor}, więc widzi {@code application.yaml}, i przed systemem
 * logowania, więc {@code json-logs} działa od pierwszej linii.
 */
public class PlatformObservabilityEnvironmentPostProcessor
    implements EnvironmentPostProcessor, Ordered {

  static final String PROPERTY_SOURCE = "platformObservabilityDefaults";

  @Override
  public void postProcessEnvironment(
      ConfigurableEnvironment environment, SpringApplication application) {
    PlatformObservabilityProperties settings =
        Binder.get(environment)
            .bind("platform.observability", PlatformObservabilityProperties.class)
            .orElseGet(PlatformObservabilityProperties::new);
    environment
        .getPropertySources()
        .addLast(new MapPropertySource(PROPERTY_SOURCE, defaults(settings)));
  }

  static Map<String, Object> defaults(PlatformObservabilityProperties settings) {
    Map<String, Object> defaults = new LinkedHashMap<>();
    defaults.put(
        "management.endpoints.web.exposure.include",
        settings.isPrometheus() ? "health,info,prometheus" : "health,info");
    defaults.put("management.endpoint.health.probes.enabled", "true");
    defaults.put("management.endpoint.health.show-details", "when-authorized");
    defaults.put("management.metrics.tags.application", "${spring.application.name:application}");
    if (settings.isPrometheus() && settings.isPublicMetrics()) {
      defaults.put(
          "platform.security.permitted-paths",
          "/actuator/health,/actuator/health/**,/actuator/info,/actuator/prometheus");
    }
    if (settings.isJsonLogs()) {
      defaults.put("logging.structured.format.console", "ecs");
    }
    return defaults;
  }

  @Override
  public int getOrder() {
    return Ordered.LOWEST_PRECEDENCE;
  }
}
