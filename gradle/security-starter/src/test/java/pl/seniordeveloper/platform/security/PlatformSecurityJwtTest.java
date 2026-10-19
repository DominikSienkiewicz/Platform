package pl.seniordeveloper.platform.security;

import static org.assertj.core.api.Assertions.assertThat;

import jakarta.servlet.Filter;
import jakarta.servlet.http.HttpServletResponse;
import java.time.Instant;
import org.junit.jupiter.api.Test;
import org.springframework.boot.autoconfigure.AutoConfigurations;
import org.springframework.boot.test.context.FilteredClassLoader;
import org.springframework.boot.test.context.assertj.AssertableWebApplicationContext;
import org.springframework.boot.test.context.runner.WebApplicationContextRunner;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpHeaders;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.BadJwtException;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;

/**
 * Tryb {@code platform.security.mode=jwt} (N-CAP-13): bez tokenu 401 problem+json z wyzwaniem
 * Bearer, poprawny token przechodzi, brak wymaganego uprawnienia daje 403 problem+json, a brak
 * zależności resource servera albo dekodera failuje start z komunikatem po angielsku. Uprawnienia
 * sprawdza tu końcówka łańcucha, tak jak zrobiłby to {@code @PreAuthorize} konsumenta.
 */
class PlatformSecurityJwtTest {

  private final WebApplicationContextRunner contextRunner =
      new WebApplicationContextRunner()
          .withConfiguration(AutoConfigurations.of(PlatformSecurityAutoConfiguration.class))
          .withUserConfiguration(JwtInfrastructure.class)
          .withPropertyValues("platform.security.mode=jwt");

  @Test
  void aRequestWithoutATokenGetsAProblemWithABearerChallenge() {
    contextRunner.run(
        context -> {
          assertThat(context).hasNotFailed();
          var response = perform(context, request(context, null), "SCOPE_orders.read");

          assertThat(response.getStatus()).isEqualTo(401);
          assertThat(response.getHeader(HttpHeaders.WWW_AUTHENTICATE)).startsWith("Bearer");
          assertThat(response.getContentType()).startsWith("application/problem+json");
          assertThat(response.getContentAsString())
              .contains("\"status\":401")
              .contains("\"instance\":\"/orders\"")
              .contains("\"detail\":\"" + PlatformSecurityProblems.UNAUTHENTICATED + "\"");
        });
  }

  @Test
  void aValidTokenReachesTheApplicationWithoutASession() {
    contextRunner.run(
        context -> {
          var request = request(context, "reader");
          var response = perform(context, request, "SCOPE_orders.read");

          assertThat(response.getStatus()).isEqualTo(200);
          assertThat(request.getSession(false)).as("jwt mode is stateless").isNull();
        });
  }

  @Test
  void aTokenWithoutTheRequiredScopeGetsAForbiddenProblem() {
    contextRunner.run(
        context -> {
          var response = perform(context, request(context, "nobody"), "SCOPE_orders.read");

          assertThat(response.getStatus()).isEqualTo(403);
          assertThat(response.getContentType()).startsWith("application/problem+json");
          assertThat(response.getContentAsString())
              .contains("\"title\":\"Forbidden\"")
              .contains("\"detail\":\"" + PlatformSecurityProblems.DENIED + "\"");
        });
  }

  @Test
  void anInvalidTokenGetsAnUnauthorizedProblem() {
    contextRunner.run(
        context -> {
          var response = perform(context, request(context, "forged"), "SCOPE_orders.read");

          assertThat(response.getStatus()).isEqualTo(401);
          assertThat(response.getHeader(HttpHeaders.WWW_AUTHENTICATE)).contains("invalid_token");
          assertThat(response.getContentType()).startsWith("application/problem+json");
        });
  }

  @Test
  void theAuthoritiesClaimMapsAnotherClaimToAuthorities() {
    contextRunner
        .withPropertyValues("platform.security.jwt.authorities-claim=roles")
        .run(
            context -> {
              var response = perform(context, request(context, "admin"), "SCOPE_admin");

              assertThat(response.getStatus()).isEqualTo(200);
            });
  }

  @Test
  void jwtModeWithoutTheResourceServerFailsAtStartupWithTheFix() {
    contextRunner
        .withClassLoader(
            new FilteredClassLoader("org.springframework.security.oauth2.server.resource"))
        .run(
            context ->
                assertThat(context)
                    .hasFailed()
                    .getFailure()
                    .rootCause()
                    .isInstanceOf(IllegalStateException.class)
                    .hasMessage(PlatformJwtResourceServer.MISSING_DEPENDENCY));
  }

  @Test
  void jwtModeWithoutADecoderFailsAtStartupWithTheFix() {
    new WebApplicationContextRunner()
        .withConfiguration(AutoConfigurations.of(PlatformSecurityAutoConfiguration.class))
        .withUserConfiguration(WebSecurityOnly.class)
        .withPropertyValues("platform.security.mode=jwt")
        .run(
            context ->
                assertThat(context)
                    .hasFailed()
                    .getFailure()
                    .rootCause()
                    .isInstanceOf(IllegalStateException.class)
                    .hasMessage(PlatformJwtResourceServer.MISSING_DECODER));
  }

  private static MockHttpServletRequest request(
      AssertableWebApplicationContext context, String token) {
    var request = new MockHttpServletRequest(context.getServletContext(), "GET", "/orders");
    request.setServletPath("/orders");
    if (token != null) {
      request.addHeader(HttpHeaders.AUTHORIZATION, "Bearer " + token);
    }
    return request;
  }

  private static MockHttpServletResponse perform(
      AssertableWebApplicationContext context, MockHttpServletRequest request, String required)
      throws Exception {
    var response = new MockHttpServletResponse();
    context
        .getBean("springSecurityFilterChain", Filter.class)
        .doFilter(
            request,
            response,
            (servletRequest, servletResponse) -> {
              var granted =
                  SecurityContextHolder.getContext().getAuthentication().getAuthorities().stream()
                      .anyMatch(authority -> authority.getAuthority().equals(required));
              if (!granted) {
                throw new AccessDeniedException("missing " + required);
              }
              ((HttpServletResponse) servletResponse).setStatus(200);
            });
    return response;
  }

  @Configuration(proxyBeanMethods = false)
  @EnableWebSecurity
  static class WebSecurityOnly {}

  @Configuration(proxyBeanMethods = false)
  @EnableWebSecurity
  static class JwtInfrastructure {

    @Bean
    JwtDecoder jwtDecoder() {
      return token ->
          switch (token) {
            case "reader" -> jwt(token, "scope", "orders.read");
            case "nobody" -> jwt(token, "scope", "profile");
            case "admin" -> jwt(token, "roles", "admin");
            default ->
                throw new BadJwtException("An error occurred while attempting to decode the Jwt");
          };
    }

    private static Jwt jwt(String token, String claim, String value) {
      return Jwt.withTokenValue(token)
          .header("alg", "none")
          .subject("user-" + token)
          .claim(claim, value)
          .issuedAt(Instant.now())
          .expiresAt(Instant.now().plusSeconds(60))
          .build();
    }
  }
}
