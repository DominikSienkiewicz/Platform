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
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;
import org.springframework.web.servlet.config.annotation.CorsRegistry;
import org.springframework.web.servlet.config.annotation.EnableWebMvc;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

class PlatformSecurityMvcCorsTest {

  private final WebApplicationContextRunner contextRunner =
      new WebApplicationContextRunner()
          .withConfiguration(AutoConfigurations.of(PlatformSecurityAutoConfiguration.class))
          .withUserConfiguration(MvcApplicationConfiguration.class);

  @Test
  void mvcInfrastructureDoesNotSuppressConfiguredPlatformOrigins() {
    contextRunner
        .withPropertyValues("platform.cors.allowed-origins=https://platform.example")
        .run(
            context -> {
              assertThat(context).hasNotFailed();
              assertThat(context.containsBean("platformCorsConfigurationSource")).isTrue();
              assertThat(context.containsBean("mvcHandlerMappingIntrospector")).isTrue();

              var allowed = preflight(context, "https://platform.example");
              assertThat(allowed.getStatus()).isEqualTo(200);
              assertThat(allowed.getHeader(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN))
                  .isEqualTo("https://platform.example");

              var rejected = preflight(context, "https://other.example");
              assertThat(rejected.getStatus()).isEqualTo(403);
              assertThat(rejected.getHeader(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN)).isNull();
            });
  }

  @Test
  void consumerSourceWinsOverMvcInfrastructureAndPlatformProperties() {
    contextRunner
        .withUserConfiguration(ConsumerCorsConfiguration.class, MvcCorsConfiguration.class)
        .withPropertyValues("platform.cors.allowed-origins=https://platform.example")
        .run(
            context -> {
              assertThat(context).hasNotFailed();
              assertThat(context).doesNotHaveBean("platformCorsConfigurationSource");
              assertThat(context.containsBean("mvcHandlerMappingIntrospector")).isTrue();
              assertThat(context.containsBean("customCorsConfigurationSource")).isTrue();

              var allowed = preflight(context, "https://consumer.example");
              assertThat(allowed.getStatus()).isEqualTo(200);
              assertThat(allowed.getHeader(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN))
                  .isEqualTo("https://consumer.example");

              assertThat(preflight(context, "https://platform.example").getStatus()).isEqualTo(403);
              assertThat(preflight(context, "https://mvc.example").getStatus()).isEqualTo(403);
            });
  }

  @Test
  void mvcCorsMappingsRemainAvailableWithoutAnExplicitSource() {
    contextRunner
        .withUserConfiguration(MvcCorsConfiguration.class)
        .run(
            context -> {
              assertThat(context).hasNotFailed();
              assertThat(context).doesNotHaveBean("platformCorsConfigurationSource");

              var allowed = preflight(context, "https://mvc.example");
              assertThat(allowed.getStatus()).isEqualTo(200);
              assertThat(allowed.getHeader(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN))
                  .isEqualTo("https://mvc.example");

              var rejected = preflight(context, "https://other.example");
              assertThat(rejected.getStatus()).isEqualTo(403);
              assertThat(rejected.getHeader(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN)).isNull();
            });
  }

  private static MockHttpServletResponse preflight(
      AssertableWebApplicationContext context, String origin) throws Exception {
    var request = new MockHttpServletRequest(context.getServletContext(), "OPTIONS", "/cors");
    request.setServletPath("/cors");
    request.addHeader(HttpHeaders.ORIGIN, origin);
    request.addHeader(HttpHeaders.ACCESS_CONTROL_REQUEST_METHOD, "GET");
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
  @EnableWebMvc
  static class MvcApplicationConfiguration {

    @Bean
    UserDetailsService users() {
      return new InMemoryUserDetailsManager(
          User.withUsername("test-user").password("{noop}test-password").roles("USER").build());
    }

    @Bean
    CorsEndpoint corsEndpoint() {
      return new CorsEndpoint();
    }
  }

  @RestController
  static class CorsEndpoint {

    @GetMapping("/cors")
    String get() {
      return "ok";
    }
  }

  @Configuration(proxyBeanMethods = false)
  static class MvcCorsConfiguration implements WebMvcConfigurer {

    @Override
    public void addCorsMappings(CorsRegistry registry) {
      registry.addMapping("/cors").allowedOrigins("https://mvc.example").allowedMethods("GET");
    }
  }

  @Configuration(proxyBeanMethods = false)
  static class ConsumerCorsConfiguration {

    @Bean
    CorsConfigurationSource customCorsConfigurationSource() {
      var configuration = new CorsConfiguration();
      configuration.setAllowedOrigins(List.of("https://consumer.example"));
      configuration.setAllowedMethods(List.of("GET"));
      var source = new UrlBasedCorsConfigurationSource();
      source.registerCorsConfiguration("/**", configuration);
      return source;
    }
  }
}
