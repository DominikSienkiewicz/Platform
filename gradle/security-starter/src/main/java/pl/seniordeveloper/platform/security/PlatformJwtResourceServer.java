package pl.seniordeveloper.platform.security;

import org.springframework.beans.factory.ListableBeanFactory;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationConverter;
import org.springframework.security.oauth2.server.resource.authentication.JwtGrantedAuthoritiesConverter;
import org.springframework.security.oauth2.server.resource.web.BearerTokenAuthenticationEntryPoint;
import org.springframework.security.oauth2.server.resource.web.access.BearerTokenAccessDeniedHandler;

/**
 * Tryb {@code platform.security.mode=jwt}. Jedyne miejsce startera, które dotyka klas resource
 * servera OAuth2 (zależność {@code compileOnly}): ładuje się dopiero po sprawdzeniu, że konsument
 * ma je na classpath, więc bez nich reszta startera działa, a tryb JWT pada z jasnym komunikatem.
 */
final class PlatformJwtResourceServer {

  static final String MARKER_CLASS =
      "org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationConverter";

  static final String MISSING_DEPENDENCY =
      "platform.security.mode=jwt needs Spring Security's OAuth2 resource server: add "
          + "org.springframework.boot:spring-boot-starter-security-oauth2-resource-server to the application's "
          + "dependencies (it is managed by the Platform BOMs, so without a version).";

  static final String MISSING_DECODER =
      "platform.security.mode=jwt needs a JwtDecoder: set spring.security.oauth2.resourceserver.jwt.issuer-uri "
          + "(or jwk-set-uri, or public-key-location), or declare a JwtDecoder bean.";

  private PlatformJwtResourceServer() {}

  static void configure(
      HttpSecurity http, PlatformSecurityProperties.Jwt jwt, ListableBeanFactory beanFactory) {
    if (beanFactory.getBeanNamesForType(JwtDecoder.class).length == 0) {
      throw new IllegalStateException(MISSING_DECODER);
    }
    var problems =
        PlatformSecurityProblems.bearer(
            new BearerTokenAuthenticationEntryPoint(), new BearerTokenAccessDeniedHandler());
    http.exceptionHandling(
        exceptions -> exceptions.authenticationEntryPoint(problems).accessDeniedHandler(problems));
    http.oauth2ResourceServer(
        server ->
            server
                .authenticationEntryPoint(problems)
                .accessDeniedHandler(problems)
                .jwt(decoder -> decoder.jwtAuthenticationConverter(converter(jwt))));
  }

  private static JwtAuthenticationConverter converter(PlatformSecurityProperties.Jwt jwt) {
    var authorities = new JwtGrantedAuthoritiesConverter();
    if (jwt.getAuthoritiesClaim() != null && !jwt.getAuthoritiesClaim().isBlank()) {
      authorities.setAuthoritiesClaimName(jwt.getAuthoritiesClaim());
    }
    var converter = new JwtAuthenticationConverter();
    converter.setJwtGrantedAuthoritiesConverter(authorities);
    return converter;
  }
}
