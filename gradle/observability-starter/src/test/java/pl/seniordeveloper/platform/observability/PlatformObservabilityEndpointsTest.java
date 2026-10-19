package pl.seniordeveloper.platform.observability;

import static org.assertj.core.api.Assertions.assertThat;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.Objects;
import org.junit.jupiter.api.Test;
import org.springframework.boot.SpringBootConfiguration;
import org.springframework.boot.WebApplicationType;
import org.springframework.boot.autoconfigure.EnableAutoConfiguration;
import org.springframework.boot.builder.SpringApplicationBuilder;
import org.springframework.boot.web.server.context.WebServerApplicationContext;
import org.springframework.context.ConfigurableApplicationContext;

/**
 * Starter na prawdziwym serwerze, jak u konsumenta: {@code spring.factories} rejestruje
 * post-processor, a sondy i Prometheus odpowiadają przez HTTP.
 */
class PlatformObservabilityEndpointsTest {

  private final HttpClient http = HttpClient.newHttpClient();

  @Test
  void theProbesAnswerAndPrometheusStaysClosedByDefault() throws Exception {
    try (ConfigurableApplicationContext context = start()) {
      assertThat(status(context, "/actuator/health/liveness")).isEqualTo(200);
      assertThat(status(context, "/actuator/health/readiness")).isEqualTo(200);
      assertThat(status(context, "/actuator/info")).isEqualTo(200);
      assertThat(status(context, "/actuator/prometheus")).isEqualTo(404);
    }
  }

  @Test
  void prometheusScrapesWithTheApplicationTagOnceRequested() throws Exception {
    try (ConfigurableApplicationContext context =
        start("--platform.observability.prometheus=true", "--spring.application.name=orders")) {
      HttpResponse<String> scrape = get(context, "/actuator/prometheus");

      assertThat(scrape.statusCode()).isEqualTo(200);
      assertThat(scrape.body()).contains("application=\"orders\"");
    }
  }

  private static ConfigurableApplicationContext start(String... arguments) {
    String[] all = new String[arguments.length + 2];
    all[0] = "--server.port=0";
    all[1] = "--spring.main.banner-mode=off";
    System.arraycopy(arguments, 0, all, 2, arguments.length);
    return new SpringApplicationBuilder(ObservedApplication.class)
        .web(WebApplicationType.SERVLET)
        .run(all);
  }

  private int status(ConfigurableApplicationContext context, String path) throws Exception {
    return get(context, path).statusCode();
  }

  private HttpResponse<String> get(ConfigurableApplicationContext context, String path)
      throws Exception {
    int port =
        Objects.requireNonNull(((WebServerApplicationContext) context).getWebServer()).getPort();
    return http.send(
        HttpRequest.newBuilder(URI.create("http://localhost:" + port + path)).build(),
        HttpResponse.BodyHandlers.ofString());
  }

  @SpringBootConfiguration(proxyBeanMethods = false)
  @EnableAutoConfiguration
  static class ObservedApplication {}
}
