package pl.seniordeveloper.platform.security;

import static org.assertj.core.api.Assertions.assertThat;

import jakarta.servlet.Filter;
import jakarta.servlet.http.HttpServletResponse;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.NoUniqueBeanDefinitionException;
import org.springframework.boot.autoconfigure.AutoConfigurations;
import org.springframework.boot.test.context.assertj.AssertableWebApplicationContext;
import org.springframework.boot.test.context.runner.WebApplicationContextRunner;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Primary;
import org.springframework.http.HttpHeaders;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.core.userdetails.User;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.provisioning.InMemoryUserDetailsManager;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

/**
 * Kontrakty startera opisane w docs/consuming.md i docs/reference.md, których nic dotąd nie
 * pinowało: wybór źródła CORS przy kilku beanach, wildcard z credentials, httpBasic wyłączony i
 * semantyka {@code permitted-paths} (zastępuje domyślną listę, nie dokleja się do niej).
 */
class PlatformSecurityContractTest {

  private final WebApplicationContextRunner contextRunner =
      new WebApplicationContextRunner()
          .withConfiguration(AutoConfigurations.of(PlatformSecurityAutoConfiguration.class))
          .withUserConfiguration(SecurityInfrastructure.class);

  @Test
  void twoExplicitCorsSourcesWithoutPrimaryFailTheContext() {
    contextRunner
        .withUserConfiguration(TwoCorsSources.class)
        .run(
            context ->
                assertThat(context)
                    .hasFailed()
                    .getFailure()
                    .rootCause()
                    .isInstanceOf(NoUniqueBeanDefinitionException.class));
  }

  @Test
  void thePrimaryCorsSourceDecidesThePreflight() {
    contextRunner
        .withUserConfiguration(TwoCorsSourcesOnePrimary.class)
        .run(
            context -> {
              assertThat(context).hasNotFailed();
              var response = perform(context, preflight(context, "https://primary.example"));
              assertThat(response.getStatus()).isEqualTo(200);
              assertThat(response.getHeader(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN))
                  .isEqualTo("https://primary.example");
              assertThat(perform(context, preflight(context, "https://other.example")).getStatus())
                  .isEqualTo(403);
            });
  }

  @Test
  void aWildcardOriginWithCredentialsFailsAtStartup() {
    contextRunner
        .withPropertyValues("platform.cors.allowed-origins=*")
        .run(
            context ->
                assertThat(context)
                    .hasFailed()
                    .getFailure()
                    .rootCause()
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("allowCredentials"));
  }

  @Test
  void withoutHttpBasicAnUnauthenticatedRequestGetsNoBasicChallenge() {
    contextRunner
        .withPropertyValues("platform.security.http-basic=false")
        .run(
            context -> {
              assertThat(context).hasNotFailed();
              var response = perform(context, request(context, "GET", "/private"));
              assertThat(response.getStatus()).isIn(401, 403);
              assertThat(response.getHeader(HttpHeaders.WWW_AUTHENTICATE)).isNull();
            });
  }

  @Test
  void permittedPathsReplaceTheDefaultsHealthIncluded() {
    contextRunner
        .withPropertyValues("platform.security.permitted-paths=/public/**")
        .run(
            context -> {
              assertThat(context).hasNotFailed();
              assertThat(perform(context, request(context, "GET", "/public/x")).getStatus())
                  .isEqualTo(204);
              assertThat(perform(context, request(context, "GET", "/actuator/health")).getStatus())
                  .isEqualTo(401);
            });
  }

  private static MockHttpServletRequest request(
      AssertableWebApplicationContext context, String method, String path) {
    var request = new MockHttpServletRequest(context.getServletContext(), method, path);
    request.setServletPath(path);
    return request;
  }

  private static MockHttpServletRequest preflight(
      AssertableWebApplicationContext context, String origin) {
    var request = request(context, "OPTIONS", "/private");
    request.addHeader(HttpHeaders.ORIGIN, origin);
    request.addHeader(HttpHeaders.ACCESS_CONTROL_REQUEST_METHOD, "POST");
    return request;
  }

  private static MockHttpServletResponse perform(
      AssertableWebApplicationContext context, MockHttpServletRequest request) throws Exception {
    var response = new MockHttpServletResponse();
    context
        .getBean("springSecurityFilterChain", Filter.class)
        .doFilter(
            request,
            response,
            (servletRequest, servletResponse) ->
                ((HttpServletResponse) servletResponse).setStatus(204));
    return response;
  }

  private static CorsConfigurationSource source(String origin) {
    var configuration = new CorsConfiguration();
    configuration.setAllowedOrigins(List.of(origin));
    configuration.setAllowedMethods(List.of("POST"));
    var source = new UrlBasedCorsConfigurationSource();
    source.registerCorsConfiguration("/**", configuration);
    return source;
  }

  @Configuration(proxyBeanMethods = false)
  @EnableWebSecurity
  static class SecurityInfrastructure {

    @Bean
    UserDetailsService users() {
      return new InMemoryUserDetailsManager(
          User.withUsername("test-user").password("{noop}test-password").roles("USER").build());
    }
  }

  @Configuration(proxyBeanMethods = false)
  static class TwoCorsSources {

    @Bean
    CorsConfigurationSource firstCorsSource() {
      return source("https://first.example");
    }

    @Bean
    CorsConfigurationSource secondCorsSource() {
      return source("https://second.example");
    }
  }

  @Configuration(proxyBeanMethods = false)
  static class TwoCorsSourcesOnePrimary {

    @Bean
    @Primary
    CorsConfigurationSource primaryCorsSource() {
      return source("https://primary.example");
    }

    @Bean
    CorsConfigurationSource otherCorsSource() {
      return source("https://other.example");
    }
  }
}
