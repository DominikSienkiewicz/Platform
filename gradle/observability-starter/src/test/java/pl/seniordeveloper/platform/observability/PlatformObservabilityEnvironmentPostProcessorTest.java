package pl.seniordeveloper.platform.observability;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.boot.SpringApplication;
import org.springframework.core.env.MapPropertySource;
import org.springframework.core.env.StandardEnvironment;

class PlatformObservabilityEnvironmentPostProcessorTest {

  private final PlatformObservabilityEnvironmentPostProcessor processor =
      new PlatformObservabilityEnvironmentPostProcessor();

  @Test
  void theDefaultsExposeHealthAndInfoWithProbesAndKeepPrometheusClosed() {
    StandardEnvironment environment = environment(Map.of());

    assertThat(environment.getProperty("management.endpoints.web.exposure.include"))
        .isEqualTo("health,info");
    assertThat(environment.getProperty("management.endpoint.health.probes.enabled"))
        .isEqualTo("true");
    assertThat(environment.getProperty("management.endpoint.health.show-details"))
        .isEqualTo("when-authorized");
    assertThat(environment.getProperty("management.metrics.tags.application"))
        .isEqualTo("application");
    assertThat(environment.getProperty("logging.structured.format.console")).isNull();
  }

  @Test
  void theApplicationTagFollowsTheApplicationName() {
    StandardEnvironment environment = environment(Map.of("spring.application.name", "orders"));

    assertThat(environment.getProperty("management.metrics.tags.application")).isEqualTo("orders");
  }

  @Test
  void prometheusIsExposedOnlyOnRequest() {
    StandardEnvironment exposed = environment(Map.of("platform.observability.prometheus", "true"));

    assertThat(exposed.getProperty("management.endpoints.web.exposure.include"))
        .isEqualTo("health,info,prometheus");
  }

  @Test
  void jsonLogsSwitchTheConsoleToEcs() {
    StandardEnvironment environment =
        environment(Map.of("platform.observability.json-logs", "true"));

    assertThat(environment.getProperty("logging.structured.format.console")).isEqualTo("ecs");
  }

  @Test
  void everyPropertyOfTheApplicationWinsOverTheDefaults() {
    StandardEnvironment environment =
        environment(
            Map.of(
                "management.endpoints.web.exposure.include", "health",
                "management.endpoint.health.probes.enabled", "false",
                "platform.observability.prometheus", "true"));

    assertThat(environment.getProperty("management.endpoints.web.exposure.include"))
        .isEqualTo("health");
    assertThat(environment.getProperty("management.endpoint.health.probes.enabled"))
        .isEqualTo("false");
    assertThat(environment.getPropertySources().stream().reduce((first, second) -> second))
        .hasValueSatisfying(
            last ->
                assertThat(last.getName())
                    .isEqualTo(PlatformObservabilityEnvironmentPostProcessor.PROPERTY_SOURCE));
  }

  @Test
  void itRunsAfterTheConfigDataOfTheApplication() {
    assertThat(processor.getOrder()).isEqualTo(Integer.MAX_VALUE);
  }

  private StandardEnvironment environment(Map<String, Object> application) {
    StandardEnvironment environment = new StandardEnvironment();
    environment.getPropertySources().addFirst(new MapPropertySource("application", application));
    processor.postProcessEnvironment(environment, new SpringApplication());
    return environment;
  }
}
