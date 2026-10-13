package pl.seniordeveloper.platform.security;

import static org.assertj.core.api.Assertions.assertThat;

import jakarta.servlet.Filter;
import jakarta.servlet.http.HttpServletResponse;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.boot.autoconfigure.AutoConfigurations;
import org.springframework.boot.test.context.assertj.AssertableWebApplicationContext;
import org.springframework.boot.test.context.runner.WebApplicationContextRunner;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpHeaders;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.core.userdetails.User;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.provisioning.InMemoryUserDetailsManager;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;
import org.springframework.web.filter.CorsFilter;

class PlatformSecurityCorsFilterTest {

  @Test
  void namedConsumerCorsFilterHandlesPreflightWithoutAPublishedConfigurationSource() {
    new WebApplicationContextRunner()
        .withConfiguration(AutoConfigurations.of(PlatformSecurityAutoConfiguration.class))
        .withUserConfiguration(ConsumerCorsFilterConfiguration.class)
        .run(
            context -> {
              assertThat(context).hasNotFailed().hasSingleBean(SecurityFilterChain.class);
              assertThat(context).hasSingleBean(CorsFilter.class);
              assertThat(context).doesNotHaveBean(CorsConfigurationSource.class);

              var allowed = preflight(context, "https://consumer.example");
              assertThat(allowed.getStatus()).isEqualTo(200);
              assertThat(allowed.getHeader(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN))
                  .isEqualTo("https://consumer.example");
              assertThat(allowed.getHeader(HttpHeaders.ACCESS_CONTROL_ALLOW_METHODS))
                  .contains("POST");

              var rejected = preflight(context, "https://other.example");
              assertThat(rejected.getStatus()).isEqualTo(403);
              assertThat(rejected.getHeader(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN)).isNull();
            });
  }

  private static MockHttpServletResponse preflight(
      AssertableWebApplicationContext context, String origin) throws Exception {
    var request = new MockHttpServletRequest(context.getServletContext(), "OPTIONS", "/private");
    request.setServletPath("/private");
    request.addHeader(HttpHeaders.ORIGIN, origin);
    request.addHeader(HttpHeaders.ACCESS_CONTROL_REQUEST_METHOD, "POST");
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

  @Configuration(proxyBeanMethods = false)
  @EnableWebSecurity
  static class ConsumerCorsFilterConfiguration {

    @Bean
    UserDetailsService users() {
      return new InMemoryUserDetailsManager(
          User.withUsername("test-user").password("{noop}test-password").roles("USER").build());
    }

    @Bean
    CorsFilter corsFilter() {
      var configuration = new CorsConfiguration();
      configuration.setAllowedOrigins(List.of("https://consumer.example"));
      configuration.setAllowedMethods(List.of("POST"));
      var source = new UrlBasedCorsConfigurationSource();
      source.registerCorsConfiguration("/**", configuration);
      return new CorsFilter(source);
    }
  }
}
