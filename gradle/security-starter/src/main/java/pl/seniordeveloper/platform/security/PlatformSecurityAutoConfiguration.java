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
import org.springframework.context.annotation.Bean;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

/**
 * Wspólny, parametryzowalny seam bezpieczeństwa/CORS. Zbiera trzy rozjechane konfiguracje
 * (BookOfStyling: stateless + permitAll + CORS; SkillSprintPlus: authenticated + httpBasic; Pragma:
 * MVC CORS) w JEDEN starter sterowany property. Każdy bean jest {@code @ConditionalOnMissingBean} —
 * konsument nadpisuje własnym, gdy potrzebuje.
 *
 * <p>Świadomie NIE zamraża postawy: domyślne wartości są bezpieczne (authenticated + csrf on), a
 * BookOfStyling odtwarza swoje zachowanie przez {@code platform.security.mode=permit-all}, {@code
 * stateless=true}, {@code csrf=false} + {@code platform.cors.allowed-origins}.
 *
 * <p>Porządek {@code before} jest konieczny: bez niego sorter Boota ustawia {@code org.springframework.*}
 * przed {@code pl.seniordeveloper.*}, domyślny chain Boota ({@code @ConditionalOnDefaultWebSecurity})
 * rejestruje się pierwszy, a chain Platform się wycofuje. Pilnuje tego
 * PlatformSecurityBootAutoConfigurationTest.
 */
@AutoConfiguration(
    beforeName = {
      "org.springframework.boot.security.autoconfigure.web.servlet.ServletWebSecurityAutoConfiguration",
      "org.springframework.boot.security.autoconfigure.actuate.web.servlet.ManagementWebSecurityAutoConfiguration"
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
      ObjectProvider<CorsConfigurationSource> corsSources)
      throws Exception {

    if (beanFactory.containsBean("corsFilter")) {
      http.cors(Customizer.withDefaults());
    } else {
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

    if (!props.isCsrf()) {
      http.csrf(csrf -> csrf.disable());
    }
    if (props.isStateless()) {
      http.sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS));
    }

    http.authorizeHttpRequests(
        auth -> {
          auth.requestMatchers(props.getPermittedPaths().toArray(String[]::new)).permitAll();
          if (props.getMode() == PlatformSecurityProperties.Mode.PERMIT_ALL) {
            auth.anyRequest().permitAll();
          } else {
            auth.anyRequest().authenticated();
          }
        });

    if (props.isHttpBasic() && props.getMode() == PlatformSecurityProperties.Mode.AUTHENTICATED) {
      http.httpBasic(Customizer.withDefaults());
    }
    return http.build();
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
    var source = new UrlBasedCorsConfigurationSource();
    source.registerCorsConfiguration("/**", config);
    return source;
  }
}
