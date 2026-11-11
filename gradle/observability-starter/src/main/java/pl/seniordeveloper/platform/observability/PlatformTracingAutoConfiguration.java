package pl.seniordeveloper.platform.observability;

import io.micrometer.observation.ObservationFilter;
import io.micrometer.tracing.otel.bridge.OtelSpan;
import org.springframework.boot.autoconfigure.AutoConfiguration;
import org.springframework.boot.autoconfigure.condition.ConditionalOnClass;
import org.springframework.context.annotation.Bean;

/**
 * Tracing startera, gdy aplikacja ma most Micrometer → OpenTelemetry (wariant {@code tracing}):
 * span serwera HTTP z odpowiedzią 5xx dostaje status {@code ERROR}, także gdy żaden wyjątek nie
 * dotarł do obserwacji, więc TraceQL {@code status = error} znajduje te same żądania, które SLO
 * liczy jako 5xx. Bez mostu na classpath auto-konfiguracja się wycofuje. Aplikacja wyłącza ją przez
 * {@code spring.autoconfigure.exclude}.
 */
@AutoConfiguration
@ConditionalOnClass(OtelSpan.class)
public class PlatformTracingAutoConfiguration {

  /** Tworzona przez Spring Boota z {@code AutoConfiguration.imports}. */
  public PlatformTracingAutoConfiguration() {}

  @Bean
  ObservationFilter platformServerErrorSpanStatus() {
    return new ServerErrorSpanStatus();
  }
}
