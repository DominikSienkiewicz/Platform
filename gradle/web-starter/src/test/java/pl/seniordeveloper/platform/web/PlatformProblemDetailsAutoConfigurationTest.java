package pl.seniordeveloper.platform.web;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.springframework.boot.autoconfigure.AutoConfigurations;
import org.springframework.boot.test.context.runner.WebApplicationContextRunner;
import org.springframework.web.servlet.mvc.method.annotation.ResponseEntityExceptionHandler;

class PlatformProblemDetailsAutoConfigurationTest {

  private final WebApplicationContextRunner runner =
      new WebApplicationContextRunner()
          .withConfiguration(AutoConfigurations.of(PlatformProblemDetailsAutoConfiguration.class));

  @Test
  void itRegistersTheHandlerByDefault() {
    runner.run(
        context -> assertThat(context).hasSingleBean(PlatformProblemDetailsExceptionHandler.class));
  }

  @Test
  void aHandlerOfTheApplicationWins() {
    runner
        .withBean(
            ResponseEntityExceptionHandler.class, () -> new ResponseEntityExceptionHandler() {})
        .run(
            context ->
                assertThat(context).doesNotHaveBean(PlatformProblemDetailsExceptionHandler.class));
  }

  @Test
  void thePropertyTurnsItOff() {
    runner
        .withPropertyValues("platform.web.problem-details.enabled=false")
        .run(
            context ->
                assertThat(context).doesNotHaveBean(PlatformProblemDetailsExceptionHandler.class));
  }
}
