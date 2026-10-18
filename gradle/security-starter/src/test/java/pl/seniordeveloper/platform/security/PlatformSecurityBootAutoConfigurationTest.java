package pl.seniordeveloper.platform.security;

import static org.assertj.core.api.Assertions.assertThat;

import jakarta.servlet.Filter;
import jakarta.servlet.http.HttpServletResponse;
import org.junit.jupiter.api.Test;
import org.springframework.boot.autoconfigure.AutoConfigurations;
import org.springframework.boot.security.autoconfigure.SecurityAutoConfiguration;
import org.springframework.boot.security.autoconfigure.UserDetailsServiceAutoConfiguration;
import org.springframework.boot.security.autoconfigure.actuate.web.servlet.ManagementWebSecurityAutoConfiguration;
import org.springframework.boot.security.autoconfigure.web.servlet.ServletWebSecurityAutoConfiguration;
import org.springframework.boot.test.context.assertj.AssertableWebApplicationContext;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.boot.test.context.runner.WebApplicationContextRunner;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.web.SecurityFilterChain;

/**
 * Starter razem z auto-konfiguracjami bezpieczeństwa Boota, które w prawdziwej aplikacji są zawsze na
 * classpath. Bez jawnego porządku sorter Boota ustawia {@code org.springframework.*} przed {@code
 * pl.seniordeveloper.*}, domyślny chain Boota rejestruje się pierwszy, a {@code @ConditionalOnMissingBean}
 * chainu Platform się wycofuje — aplikacja dostaje domyślne security Boota zamiast skonfigurowanego trybu.
 */
class PlatformSecurityBootAutoConfigurationTest {

  private static final AutoConfigurations BOOT_SECURITY =
      AutoConfigurations.of(
          SecurityAutoConfiguration.class,
          UserDetailsServiceAutoConfiguration.class,
          ServletWebSecurityAutoConfiguration.class,
          PlatformSecurityAutoConfiguration.class);

  @Test
  void platformChainWinsOverBootsDefaultWebSecurity() {
    new WebApplicationContextRunner()
        .withConfiguration(BOOT_SECURITY)
        .withPropertyValues("platform.security.mode=permit-all")
        .run(
            context -> {
              assertThat(context).hasNotFailed();
              assertThat(context.getBeansOfType(SecurityFilterChain.class).keySet())
                  .containsExactly("platformSecurityFilterChain");
              assertThat(perform(context, "/private").getStatus()).isEqualTo(204);
            });
  }

  @Test
  void platformChainWinsOverBootsManagementWebSecurity() {
    new WebApplicationContextRunner()
        .withConfiguration(BOOT_SECURITY)
        .withConfiguration(AutoConfigurations.of(ManagementWebSecurityAutoConfiguration.class))
        .withPropertyValues("platform.security.mode=permit-all")
        .run(
            context -> {
              assertThat(context).hasNotFailed();
              assertThat(context.getBeansOfType(SecurityFilterChain.class).keySet())
                  .containsExactly("platformSecurityFilterChain");
            });
  }

  @Test
  void aNonWebApplicationStartsWithoutAFilterChain() {
    new ApplicationContextRunner()
        .withConfiguration(AutoConfigurations.of(PlatformSecurityAutoConfiguration.class))
        .run(
            context -> {
              assertThat(context).hasNotFailed();
              assertThat(context).doesNotHaveBean(SecurityFilterChain.class);
            });
  }

  private static MockHttpServletResponse perform(AssertableWebApplicationContext context, String path)
      throws Exception {
    var request = new MockHttpServletRequest(context.getServletContext(), "GET", path);
    request.setServletPath(path);
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
}
