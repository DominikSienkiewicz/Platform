package pl.seniordeveloper.platform.security;

import static org.assertj.core.api.Assertions.assertThat;

import jakarta.servlet.Filter;
import jakarta.servlet.http.HttpServletResponse;
import java.nio.charset.StandardCharsets;
import java.util.Base64;
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
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.core.userdetails.User;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.provisioning.InMemoryUserDetailsManager;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.csrf.CsrfToken;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

class PlatformSecurityAutoConfigurationTest {

  private final WebApplicationContextRunner contextRunner =
      new WebApplicationContextRunner()
          .withConfiguration(AutoConfigurations.of(PlatformSecurityAutoConfiguration.class))
          .withUserConfiguration(SecurityInfrastructureConfiguration.class);

  @Test
  void defaultsRejectUnauthenticatedRequestsWithoutRequiringCorsConfiguration() {
    contextRunner.run(
        context -> {
          assertThat(context).hasNotFailed().hasSingleBean(SecurityFilterChain.class);
          assertThat(context).doesNotHaveBean(CorsConfigurationSource.class);

          var response = perform(context, request(context, "GET", "/private"));

          assertThat(response.getStatus()).isEqualTo(401);
          assertThat(response.getHeader(HttpHeaders.WWW_AUTHENTICATE)).startsWith("Basic ");
        });
  }

  @Test
  void defaultsAllowHealthChecksWithoutAuthentication() {
    contextRunner.run(
        context -> {
          assertThat(context).hasNotFailed();

          var response = perform(context, request(context, "GET", "/actuator/health"));

          assertThat(response.getStatus()).isEqualTo(204);
        });
  }

  @Test
  void defaultsRequireCsrfTokenForAuthenticatedWrites() {
    contextRunner.run(
        context -> {
          assertThat(context).hasNotFailed();
          var authenticatedRead = authenticatedRequest(context, "GET", "/private");
          assertThat(perform(context, authenticatedRead).getStatus()).isEqualTo(204);

          var missingTokenResponse =
              perform(context, authenticatedRequest(context, "POST", "/private"));
          assertThat(missingTokenResponse.getStatus()).isEqualTo(403);

          var csrfToken = (CsrfToken) authenticatedRead.getAttribute(CsrfToken.class.getName());
          assertThat(csrfToken).isNotNull();
          var tokenValue = csrfToken.getToken();
          var authenticatedWrite = authenticatedRequest(context, "POST", "/private");
          authenticatedWrite.setSession(authenticatedRead.getSession(false));
          authenticatedWrite.addHeader(csrfToken.getHeaderName(), tokenValue);

          assertThat(perform(context, authenticatedWrite).getStatus()).isEqualTo(204);
        });
  }

  @Test
  void permitAllDoesNotImplicitlyDisableCsrf() {
    contextRunner
        .withPropertyValues("platform.security.mode=permit-all")
        .run(
            context -> {
              assertThat(context).hasNotFailed();

              assertThat(perform(context, request(context, "GET", "/private")).getStatus())
                  .isEqualTo(204);
              assertThat(perform(context, request(context, "POST", "/private")).getStatus())
                  .isEqualTo(403);
            });
  }

  @Test
  void explicitPermitAllAndDisabledCsrfAllowStatelessWrites() {
    contextRunner
        .withPropertyValues(
            "platform.security.mode=permit-all",
            "platform.security.csrf=false",
            "platform.security.stateless=true")
        .run(
            context -> {
              assertThat(context).hasNotFailed();
              var write = request(context, "POST", "/private");

              assertThat(perform(context, write).getStatus()).isEqualTo(204);
              assertThat(write.getSession(false)).isNull();
            });
  }

  @Test
  void userSecurityFilterChainReplacesThePlatformChain() {
    contextRunner
        .withUserConfiguration(UserSecurityConfiguration.class)
        .withPropertyValues("platform.security.mode=permit-all", "platform.security.csrf=false")
        .run(
            context -> {
              assertThat(context).hasNotFailed().hasSingleBean(SecurityFilterChain.class);
              assertThat(context).doesNotHaveBean("platformSecurityFilterChain");
              assertThat(context.getBean(SecurityFilterChain.class))
                  .isSameAs(context.getBean("userSecurityFilterChain"));

              var response = perform(context, request(context, "GET", "/actuator/health"));

              assertThat(response.getStatus()).isEqualTo(403);
            });
  }

  @Test
  void configuredCorsOriginsAllowMatchingPreflightAndRejectOtherOrigins() {
    contextRunner
        .withPropertyValues("platform.cors.allowed-origins=https://client.example")
        .run(
            context -> {
              assertThat(context).hasNotFailed().hasSingleBean(CorsConfigurationSource.class);

              var allowed = perform(context, preflight(context, "https://client.example"));
              assertThat(allowed.getStatus()).isEqualTo(200);
              assertThat(allowed.getHeader(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN))
                  .isEqualTo("https://client.example");
              assertThat(allowed.getHeader(HttpHeaders.ACCESS_CONTROL_ALLOW_CREDENTIALS))
                  .isEqualTo("true");
              assertThat(allowed.getHeader(HttpHeaders.ACCESS_CONTROL_ALLOW_METHODS))
                  .contains("POST");

              var rejected = perform(context, preflight(context, "https://other.example"));
              assertThat(rejected.getStatus()).isEqualTo(403);
              assertThat(rejected.getHeader(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN)).isNull();
            });
  }

  @Test
  void userCorsConfigurationSourceReplacesPlatformOriginsRegardlessOfBeanName() {
    contextRunner
        .withUserConfiguration(UserCorsConfiguration.class)
        .withPropertyValues("platform.cors.allowed-origins=https://platform.example")
        .run(
            context -> {
              assertThat(context).hasNotFailed().hasSingleBean(CorsConfigurationSource.class);
              assertThat(context).doesNotHaveBean("platformCorsConfigurationSource");
              assertThat(context.getBean(CorsConfigurationSource.class))
                  .isSameAs(context.getBean("customCorsConfigurationSource"));

              var allowed = perform(context, preflight(context, "https://custom.example"));
              assertThat(allowed.getStatus()).isEqualTo(200);
              assertThat(allowed.getHeader(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN))
                  .isEqualTo("https://custom.example");

              var rejected = perform(context, preflight(context, "https://platform.example"));
              assertThat(rejected.getStatus()).isEqualTo(403);
              assertThat(rejected.getHeader(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN)).isNull();
            });
  }

  private static MockHttpServletRequest request(
      AssertableWebApplicationContext context, String method, String path) {
    var request = new MockHttpServletRequest(context.getServletContext(), method, path);
    request.setServletPath(path);
    return request;
  }

  private static MockHttpServletRequest authenticatedRequest(
      AssertableWebApplicationContext context, String method, String path) {
    var request = request(context, method, path);
    var credentials = "test-user:test-password".getBytes(StandardCharsets.UTF_8);
    request.addHeader(
        HttpHeaders.AUTHORIZATION, "Basic " + Base64.getEncoder().encodeToString(credentials));
    return request;
  }

  private static MockHttpServletRequest preflight(
      AssertableWebApplicationContext context, String origin) {
    var request = request(context, "OPTIONS", "/private");
    request.addHeader(HttpHeaders.ORIGIN, origin);
    request.addHeader(HttpHeaders.ACCESS_CONTROL_REQUEST_METHOD, "POST");
    request.addHeader(HttpHeaders.ACCESS_CONTROL_REQUEST_HEADERS, "Content-Type");
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

  @Configuration(proxyBeanMethods = false)
  @EnableWebSecurity
  static class SecurityInfrastructureConfiguration {

    @Bean
    UserDetailsService users() {
      return new InMemoryUserDetailsManager(
          User.withUsername("test-user").password("{noop}test-password").roles("USER").build());
    }
  }

  @Configuration(proxyBeanMethods = false)
  static class UserSecurityConfiguration {

    @Bean
    SecurityFilterChain userSecurityFilterChain(HttpSecurity http) {
      return http.authorizeHttpRequests(auth -> auth.anyRequest().denyAll()).build();
    }
  }

  @Configuration(proxyBeanMethods = false)
  static class UserCorsConfiguration {

    @Bean
    CorsConfigurationSource customCorsConfigurationSource() {
      var configuration = new CorsConfiguration();
      configuration.setAllowedOrigins(List.of("https://custom.example"));
      configuration.setAllowedMethods(List.of("POST"));
      configuration.setAllowedHeaders(List.of("Content-Type"));
      var source = new UrlBasedCorsConfigurationSource();
      source.registerCorsConfiguration("/**", configuration);
      return source;
    }
  }
}
