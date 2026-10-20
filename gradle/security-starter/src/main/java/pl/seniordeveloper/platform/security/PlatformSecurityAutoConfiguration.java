package pl.seniordeveloper.platform.security;

import java.util.Map;
import org.springframework.beans.factory.ListableBeanFactory;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.boot.autoconfigure.AutoConfiguration;
import org.springframework.boot.autoconfigure.condition.ConditionalOnClass;
import org.springframework.boot.autoconfigure.condition.ConditionalOnMissingBean;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.autoconfigure.condition.ConditionalOnWebApplication;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.ApplicationContext;
import org.springframework.context.annotation.Bean;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.util.ClassUtils;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

/**
 * Wspólny, parametryzowalny seam bezpieczeństwa/CORS. Zbiera dwie rozjechane konfiguracje
 * (BookOfStyling: stateless + permitAll + CORS; SkillSprintPlus: authenticated + httpBasic) w JEDEN
 * starter sterowany property. Każdy bean jest {@code @ConditionalOnMissingBean} — konsument
 * nadpisuje własnym, gdy potrzebuje.
 *
 * <p>Świadomie NIE zamraża postawy: domyślne wartości są bezpieczne (authenticated + csrf on), a
 * BookOfStyling odtwarza swoje zachowanie przez {@code platform.security.mode=permit-all}, {@code
 * stateless=true}, {@code csrf=false} + {@code platform.cors.allowed-origins}.
 *
 * <p>Porządek {@code before} jest konieczny: bez niego sorter Boota ustawia {@code
 * org.springframework.*} przed {@code pl.seniordeveloper.*}, domyślny chain Boota
 * ({@code @ConditionalOnDefaultWebSecurity}) rejestruje się pierwszy, a chain Platform się
 * wycofuje. Pilnuje tego PlatformSecurityBootAutoConfigurationTest. Ten sam warunek ma chain
 * resource servera Boota, więc i on stoi na liście.
 *
 * <p>401 i 403 są zawsze {@code application/problem+json} (PlatformSecurityProblems), z nagłówkiem
 * {@code WWW-Authenticate} trybu: Basic przy httpBasic, Bearer w trybie JWT.
 */
@AutoConfiguration(
    beforeName = {
      "org.springframework.boot.security.autoconfigure.web.servlet.ServletWebSecurityAutoConfiguration",
      "org.springframework.boot.security.autoconfigure.actuate.web.servlet.ManagementWebSecurityAutoConfiguration",
      "org.springframework.boot.security.oauth2.server.resource.autoconfigure.web.OAuth2ResourceServerWebSecurityAutoConfiguration"
    })
@ConditionalOnWebApplication(type = ConditionalOnWebApplication.Type.SERVLET)
@ConditionalOnClass(SecurityFilterChain.class)
@EnableConfigurationProperties({PlatformSecurityProperties.class, PlatformCorsProperties.class})
public class PlatformSecurityAutoConfiguration {

  @Bean
  @ConditionalOnMissingBean
  public SecurityFilterChain platformSecurityFilterChain(
      HttpSecurity http,
      PlatformSecurityProperties props,
      ListableBeanFactory beanFactory,
      ApplicationContext context,
      ObjectProvider<CorsConfigurationSource> corsSources) {
    boolean jwt = props.getMode() == PlatformSecurityProperties.Mode.JWT;
    if (jwt
        && !ClassUtils.isPresent(
            PlatformJwtResourceServer.MARKER_CLASS, context.getClassLoader())) {
      throw new IllegalStateException(PlatformJwtResourceServer.MISSING_DEPENDENCY);
    }

    configureCors(http, beanFactory, corsSources);
    configureCsrf(http, props.getCsrf());
    // Tryb JWT jest bezstanowy z definicji: token w każdym żądaniu, bez sesji do przejęcia.
    if (props.isStateless() || jwt) {
      http.sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS));
    }
    configureAuthorization(http, props);
    configureAuthentication(http, props, beanFactory);
    return http.build();
  }

  private static void configureCors(
      HttpSecurity http,
      ListableBeanFactory beanFactory,
      ObjectProvider<CorsConfigurationSource> corsSources) {
    if (beanFactory.containsBean("corsFilter")) {
      http.cors(Customizer.withDefaults());
      return;
    }
    // MVC supplies a fallback source; an explicit application source takes precedence.
    var explicitCorsSources =
        beanFactory.getBeansOfType(CorsConfigurationSource.class).entrySet().stream()
            .filter(entry -> !entry.getKey().equals("mvcHandlerMappingIntrospector"))
            .map(Map.Entry::getValue)
            .toList();
    var corsSource =
        explicitCorsSources.size() == 1
            ? explicitCorsSources.getFirst()
            : corsSources.getIfAvailable();
    if (corsSource != null) {
      http.cors(cors -> cors.configurationSource(corsSource));
    }
  }

  private static void configureCsrf(HttpSecurity http, PlatformSecurityProperties.Csrf mode) {
    if (mode == PlatformSecurityProperties.Csrf.OFF) {
      http.csrf(csrf -> csrf.disable());
    } else if (mode == PlatformSecurityProperties.Csrf.SPA) {
      http.csrf(csrf -> csrf.spa());
    }
  }

  private static void configureAuthorization(HttpSecurity http, PlatformSecurityProperties props) {
    boolean permitAll = props.getMode() == PlatformSecurityProperties.Mode.PERMIT_ALL;
    http.authorizeHttpRequests(
        auth -> {
          auth.requestMatchers(props.getPermittedPaths().toArray(String[]::new)).permitAll();
          if (permitAll) {
            auth.anyRequest().permitAll();
          } else {
            auth.anyRequest().authenticated();
          }
        });
  }

  private static void configureAuthentication(
      HttpSecurity http, PlatformSecurityProperties props, ListableBeanFactory beanFactory) {
    if (props.getMode() == PlatformSecurityProperties.Mode.JWT) {
      PlatformJwtResourceServer.configure(http, props.getJwt(), beanFactory);
    } else if (props.isHttpBasic()
        && props.getMode() == PlatformSecurityProperties.Mode.AUTHENTICATED) {
      var problems = PlatformSecurityProblems.basic();
      http.exceptionHandling(
          exceptions ->
              exceptions.authenticationEntryPoint(problems).accessDeniedHandler(problems));
      http.httpBasic(basic -> basic.authenticationEntryPoint(problems));
    } else {
      var problems = PlatformSecurityProblems.plain();
      http.exceptionHandling(
          exceptions ->
              exceptions.authenticationEntryPoint(problems).accessDeniedHandler(problems));
    }
  }

  @Bean
  @ConditionalOnMissingBean(
      value = CorsConfigurationSource.class,
      ignoredType = "org.springframework.web.servlet.handler.HandlerMappingIntrospector")
  @ConditionalOnProperty(prefix = "platform.cors", name = "allowed-origins")
  public CorsConfigurationSource platformCorsConfigurationSource(PlatformCorsProperties cors) {
    var config = new CorsConfiguration();
    config.setAllowedOrigins(cors.getAllowedOrigins());
    config.setAllowedMethods(cors.getAllowedMethods());
    config.setAllowedHeaders(cors.getAllowedHeaders());
    config.setAllowCredentials(cors.isAllowCredentials());
    // Wildcard origin z credentials Spring odrzuca dopiero przy pierwszym żądaniu CORS; tu błąd
    // przy starcie.
    config.validateAllowCredentials();
    var source = new UrlBasedCorsConfigurationSource();
    source.registerCorsConfiguration("/**", config);
    return source;
  }
}
