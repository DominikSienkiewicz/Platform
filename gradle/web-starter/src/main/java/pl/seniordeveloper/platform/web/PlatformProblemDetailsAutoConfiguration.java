package pl.seniordeveloper.platform.web;

import org.springframework.boot.autoconfigure.AutoConfiguration;
import org.springframework.boot.autoconfigure.condition.ConditionalOnClass;
import org.springframework.boot.autoconfigure.condition.ConditionalOnMissingBean;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.autoconfigure.condition.ConditionalOnWebApplication;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.web.servlet.mvc.method.annotation.ResponseEntityExceptionHandler;

/**
 * Rejestruje {@link PlatformProblemDetailsExceptionHandler} przed auto-konfiguracją Spring MVC,
 * więc {@code ProblemDetailsExceptionHandler} Boota się wycofuje. Własny {@code
 * ResponseEntityExceptionHandler} konsumenta wygrywa ({@code @ConditionalOnMissingBean}), a {@code
 * platform.web.problem-details.enabled=false} wyłącza całość.
 */
@AutoConfiguration(
    beforeName = "org.springframework.boot.webmvc.autoconfigure.WebMvcAutoConfiguration")
@ConditionalOnWebApplication(type = ConditionalOnWebApplication.Type.SERVLET)
@ConditionalOnClass(ResponseEntityExceptionHandler.class)
@ConditionalOnProperty(
    prefix = "platform.web.problem-details",
    name = "enabled",
    havingValue = "true",
    matchIfMissing = true)
@EnableConfigurationProperties(PlatformProblemDetailsProperties.class)
public class PlatformProblemDetailsAutoConfiguration {

  /**
   * Handler kontraktu błędów.
   *
   * @param properties przełączniki {@code platform.web.problem-details.*}
   * @return advice mapujący wyjątki na Problem Details
   */
  @Bean
  @ConditionalOnMissingBean(ResponseEntityExceptionHandler.class)
  public PlatformProblemDetailsExceptionHandler platformProblemDetailsExceptionHandler(
      PlatformProblemDetailsProperties properties) {
    return new PlatformProblemDetailsExceptionHandler(properties.isLegacyMessage());
  }
}
