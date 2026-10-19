package pl.seniordeveloper.platform.security;

import static org.assertj.core.api.Assertions.assertThat;

import jakarta.servlet.Filter;
import jakarta.servlet.http.Cookie;
import jakarta.servlet.http.HttpServletResponse;
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

/**
 * 401 i 403 jako {@code application/problem+json} w trybach bez JWT (N-CAP-13), oraz {@code
 * platform.security.csrf=spa}: token w ciasteczku {@code XSRF-TOKEN}, odsyłany w {@code
 * X-XSRF-TOKEN}.
 */
class PlatformSecurityProblemDetailsTest {

  private final WebApplicationContextRunner contextRunner =
      new WebApplicationContextRunner()
          .withConfiguration(AutoConfigurations.of(PlatformSecurityAutoConfiguration.class))
          .withUserConfiguration(SecurityInfrastructure.class);

  @Test
  void anUnauthenticatedRequestGetsAProblemAndTheBasicChallenge() {
    contextRunner.run(
        context -> {
          var response = perform(context, request(context, "GET", "/private"));

          assertThat(response.getStatus()).isEqualTo(401);
          assertThat(response.getHeader(HttpHeaders.WWW_AUTHENTICATE))
              .isEqualTo("Basic realm=\"Realm\"");
          assertThat(response.getContentType()).startsWith("application/problem+json");
          assertThat(response.getContentAsString())
              .isEqualTo(
                  "{\"title\":\"Unauthorized\",\"status\":401,\"detail\":\""
                      + PlatformSecurityProblems.UNAUTHENTICATED
                      + "\",\"instance\":\"/private\",\"message\":\""
                      + PlatformSecurityProblems.UNAUTHENTICATED
                      + "\"}");
        });
  }

  @Test
  void aWriteWithoutTheCsrfTokenGetsAForbiddenProblem() {
    contextRunner
        .withPropertyValues("platform.security.mode=permit-all")
        .run(
            context -> {
              var response = perform(context, request(context, "POST", "/private"));

              assertThat(response.getStatus()).isEqualTo(403);
              assertThat(response.getContentType()).startsWith("application/problem+json");
              assertThat(response.getContentAsString()).contains("\"title\":\"Forbidden\"");
            });
  }

  @Test
  void spaCsrfHandsTheTokenOutInACookieAndAcceptsItBackInTheHeader() {
    contextRunner
        .withPropertyValues("platform.security.mode=permit-all", "platform.security.csrf=spa")
        .run(
            context -> {
              assertThat(context).hasNotFailed();
              var read = perform(context, request(context, "GET", "/private"));
              var cookie = read.getCookie("XSRF-TOKEN");
              assertThat(cookie).as("the token cookie the browser client reads").isNotNull();
              assertThat(cookie.isHttpOnly()).as("JavaScript must read it").isFalse();

              var write = request(context, "POST", "/private");
              write.setCookies(new Cookie("XSRF-TOKEN", cookie.getValue()));
              write.addHeader("X-XSRF-TOKEN", cookie.getValue());
              assertThat(perform(context, write).getStatus()).isEqualTo(204);

              var forged = request(context, "POST", "/private");
              forged.setCookies(new Cookie("XSRF-TOKEN", cookie.getValue()));
              forged.addHeader("X-XSRF-TOKEN", "forged");
              assertThat(perform(context, forged).getStatus()).isEqualTo(403);
            });
  }

  @Test
  void theOldBooleanCsrfValuesStillBind() {
    contextRunner
        .withPropertyValues("platform.security.csrf=true")
        .run(
            context ->
                assertThat(context.getBean(PlatformSecurityProperties.class).getCsrf())
                    .isEqualTo(PlatformSecurityProperties.Csrf.ON));
    contextRunner
        .withPropertyValues("platform.security.csrf=false")
        .run(
            context ->
                assertThat(context.getBean(PlatformSecurityProperties.class).getCsrf())
                    .isEqualTo(PlatformSecurityProperties.Csrf.OFF));
  }

  @Test
  void quotingKeepsTheJsonValid() {
    assertThat(PlatformSecurityProblems.quote("a\"b\\c\n\u0001"))
        .isEqualTo("\"a\\\"b\\\\c\\n\\u0001\"");
  }

  private static MockHttpServletRequest request(
      AssertableWebApplicationContext context, String method, String path) {
    var request = new MockHttpServletRequest(context.getServletContext(), method, path);
    request.setServletPath(path);
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
  static class SecurityInfrastructure {

    @Bean
    UserDetailsService users() {
      return new InMemoryUserDetailsManager(
          User.withUsername("test-user").password("{noop}test-password").roles("USER").build());
    }
  }
}
