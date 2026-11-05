package pl.seniordeveloper.platform.security;

import java.util.List;
import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Konfiguracja łańcucha bezpieczeństwa — starter NIE zamraża postawy (wszystko sterowane property).
 * Domyślnie: {@code AUTHENTICATED} + httpBasic + CSRF on, ścieżki health/info przepuszczone (bramka
 * deployu); {@code JWT} to resource server OAuth2, a {@code csrf=spa} — token w ciasteczku dla SPA.
 * BookOfStyling ({@code permit-all} + stateless + csrf off) i SkillSprintPlus (domyślne) różniły
 * się tylko wartościami — teraz to property.
 */
@ConfigurationProperties(prefix = "platform.security")
public class PlatformSecurityProperties {

  /** Postawa łańcucha wobec żądań spoza {@code permitted-paths}. */
  public enum Mode {
    /** Reszta żądań wymaga uwierzytelnienia (domyślne — bezpieczne). */
    AUTHENTICATED,
    /** Wszystko {@code permitAll} (np. BFF/stateless za bramą, dev). */
    PERMIT_ALL,
    /**
     * Resource server OAuth2: reszta żądań wymaga tokenu JWT w {@code Authorization: Bearer}, bez
     * sesji. Dekoder konfiguruje Boot z {@code spring.security.oauth2.resourceserver.jwt.*};
     * zależność dokłada konsument (spring-boot-starter-security-oauth2-resource-server).
     */
    JWT
  }

  /**
   * CSRF: {@code true}/{@code false} wiążą się z ON/OFF (Boot), więc dotychczasowe wartości
   * działają.
   */
  public enum Csrf {
    /** Token w sesji, jak domyślny Spring Security. */
    ON,
    /** Bez ochrony CSRF — tylko dla API bez uwierzytelnienia ciasteczkiem. */
    OFF,
    /**
     * SPA: token w ciasteczku {@code XSRF-TOKEN} czytelnym dla JavaScriptu, odsyłany w nagłówku
     * {@code X-XSRF-TOKEN} (Spring Security {@code csrf.spa()}; api-client: opcja {@code xsrf}).
     */
    SPA
  }

  /**
   * AUTHENTICATED requires authentication for every path not permitted; PERMIT_ALL permits every
   * request.
   */
  private Mode mode = Mode.AUTHENTICATED;

  /** Disables the HTTP session, for token-authenticated APIs. */
  private boolean stateless = false;

  /**
   * CSRF protection: ON (session token), OFF (only for an API without cookie authentication) or SPA
   * (a cookie the browser client echoes in X-XSRF-TOKEN). true and false still mean ON and OFF.
   */
  private Csrf csrf = Csrf.ON;

  /** HTTP Basic authentication. */
  private boolean httpBasic = true;

  /** Paths that never require authentication; the deploy health gate needs the defaults. */
  private List<String> permittedPaths =
      List.of("/actuator/health", "/actuator/health/**", "/actuator/info");

  /** Settings of mode=jwt. */
  private final Jwt jwt = new Jwt();

  /** Tworzy właściwości z bezpiecznymi wartościami domyślnymi; Boot wiąże je przez settery. */
  public PlatformSecurityProperties() {
    // Pusty: jawny tylko po to, żeby opisać go w Javadoc (javadoc -Werror).
  }

  /** Ustawienia trybu JWT; dekoder i issuer zostają we właściwościach Boota. */
  public static class Jwt {

    /**
     * JWT claim that carries the authorities, for an identity provider that does not use scope or
     * scp; unset reads scope and scp. Each value becomes an authority with the SCOPE_ prefix.
     */
    private String authoritiesClaim;

    /** Tworzy ustawienia bez własnego claimu: uprawnienia pochodzą ze scope i scp. */
    public Jwt() {
      // Pusty: jawny tylko po to, żeby opisać go w Javadoc (javadoc -Werror).
    }

    /**
     * Claim z uprawnieniami.
     *
     * @return nazwa claimu; {@code null}, gdy uprawnienia pochodzą ze scope i scp
     */
    public String getAuthoritiesClaim() {
      return authoritiesClaim;
    }

    /**
     * Ustawia claim z uprawnieniami, gdy dostawca tożsamości nie używa scope ani scp.
     *
     * @param authoritiesClaim nazwa claimu; każda jego wartość staje się uprawnieniem z prefiksem
     *     {@code SCOPE_}
     */
    public void setAuthoritiesClaim(String authoritiesClaim) {
      this.authoritiesClaim = authoritiesClaim;
    }
  }

  /**
   * Postawa łańcucha.
   *
   * @return tryb; domyślnie {@link Mode#AUTHENTICATED}
   */
  public Mode getMode() {
    return mode;
  }

  /**
   * Ustawia postawę łańcucha.
   *
   * @param mode tryb obowiązujący żądania spoza {@code permitted-paths}
   */
  public void setMode(Mode mode) {
    this.mode = mode;
  }

  /**
   * Czy łańcuch wyłącza sesję HTTP. Tryb {@link Mode#JWT} wyłącza ją niezależnie od tej wartości.
   *
   * @return {@code true}, gdy sesja jest wyłączona; domyślnie {@code false}
   */
  public boolean isStateless() {
    return stateless;
  }

  /**
   * Ustawia, czy łańcuch wyłącza sesję HTTP.
   *
   * @param stateless {@code true} wyłącza sesję, dla API uwierzytelnianego tokenem
   */
  public void setStateless(boolean stateless) {
    this.stateless = stateless;
  }

  /**
   * Ochrona CSRF.
   *
   * @return tryb ochrony; domyślnie {@link Csrf#ON}
   */
  public Csrf getCsrf() {
    return csrf;
  }

  /**
   * Ustawia ochronę CSRF.
   *
   * @param csrf tryb ochrony; {@link Csrf#OFF} tylko dla API bez uwierzytelnienia ciasteczkiem
   */
  public void setCsrf(Csrf csrf) {
    this.csrf = csrf;
  }

  /**
   * Czy tryb {@link Mode#AUTHENTICATED} włącza HTTP Basic; inne tryby ignorują tę wartość.
   *
   * @return {@code true}, gdy HTTP Basic jest włączony; domyślnie {@code true}
   */
  public boolean isHttpBasic() {
    return httpBasic;
  }

  /**
   * Ustawia, czy tryb {@link Mode#AUTHENTICATED} włącza HTTP Basic.
   *
   * @param httpBasic {@code true} włącza HTTP Basic
   */
  public void setHttpBasic(boolean httpBasic) {
    this.httpBasic = httpBasic;
  }

  /**
   * Ścieżki, które nigdy nie wymagają uwierzytelnienia.
   *
   * @return wzorce ścieżek; domyślnie health i info Actuatora, których potrzebuje bramka deployu
   */
  public List<String> getPermittedPaths() {
    return permittedPaths;
  }

  /**
   * Ustawia ścieżki, które nigdy nie wymagają uwierzytelnienia. Lista zastępuje wartości domyślne.
   *
   * @param permittedPaths wzorce ścieżek; bramka deployu potrzebuje health i info Actuatora
   */
  public void setPermittedPaths(List<String> permittedPaths) {
    this.permittedPaths = permittedPaths;
  }

  /**
   * Ustawienia trybu {@link Mode#JWT}.
   *
   * @return zawsze ta sama, niepusta instancja ustawień
   */
  public Jwt getJwt() {
    return jwt;
  }
}
