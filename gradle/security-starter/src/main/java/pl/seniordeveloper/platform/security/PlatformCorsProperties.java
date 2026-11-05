package pl.seniordeveloper.platform.security;

import java.util.List;
import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * CORS sterowane property. Bean {@code CorsConfigurationSource} rejestrowany TYLKO gdy ustawiono
 * {@code platform.cors.allowed-origins} (inaczej brak CORS — zachowanie domyślne Spring Security).
 * Zbiera warianty z BookOfStyling ({@code app.cors.allowed-origins}) i Pragmy (hardkod portów dev).
 */
@ConfigurationProperties(prefix = "platform.cors")
public class PlatformCorsProperties {

  /** Allowed origins; setting it registers the Platform CORS configuration for every path. */
  private List<String> allowedOrigins = List.of();

  /** Allowed HTTP methods. */
  private List<String> allowedMethods = List.of("GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS");

  /** Allowed request headers. */
  private List<String> allowedHeaders = List.of("*");

  /** Whether the browser may send credentials, such as cookies, with a cross-origin request. */
  private boolean allowCredentials = true;

  /** Tworzy właściwości z wartościami domyślnymi; Boot wiąże je przez settery. */
  public PlatformCorsProperties() {
    // Pusty: jawny tylko po to, żeby opisać go w Javadoc (javadoc -Werror).
  }

  /**
   * Dozwolone originy.
   *
   * @return originy z {@code platform.cors.allowed-origins}; domyślnie pusta lista
   */
  public List<String> getAllowedOrigins() {
    return allowedOrigins;
  }

  /**
   * Ustawia dozwolone originy.
   *
   * @param allowedOrigins originy, dla których Platform rejestruje konfigurację CORS
   */
  public void setAllowedOrigins(List<String> allowedOrigins) {
    this.allowedOrigins = allowedOrigins;
  }

  /**
   * Dozwolone metody HTTP.
   *
   * @return metody; domyślnie GET, POST, PUT, PATCH, DELETE i OPTIONS
   */
  public List<String> getAllowedMethods() {
    return allowedMethods;
  }

  /**
   * Ustawia dozwolone metody HTTP.
   *
   * @param allowedMethods metody dopuszczone w żądaniach cross-origin
   */
  public void setAllowedMethods(List<String> allowedMethods) {
    this.allowedMethods = allowedMethods;
  }

  /**
   * Dozwolone nagłówki żądania.
   *
   * @return nagłówki; domyślnie {@code *}
   */
  public List<String> getAllowedHeaders() {
    return allowedHeaders;
  }

  /**
   * Ustawia dozwolone nagłówki żądania.
   *
   * @param allowedHeaders nagłówki dopuszczone w żądaniach cross-origin
   */
  public void setAllowedHeaders(List<String> allowedHeaders) {
    this.allowedHeaders = allowedHeaders;
  }

  /**
   * Czy przeglądarka może wysłać poświadczenia, np. ciasteczka, w żądaniu cross-origin.
   *
   * @return {@code true}, gdy poświadczenia są dozwolone; domyślnie {@code true}
   */
  public boolean isAllowCredentials() {
    return allowCredentials;
  }

  /**
   * Ustawia, czy przeglądarka może wysłać poświadczenia w żądaniu cross-origin.
   *
   * @param allowCredentials {@code true} dopuszcza poświadczenia; origin {@code *} wyklucza tę
   *     wartość i wywala start aplikacji
   */
  public void setAllowCredentials(boolean allowCredentials) {
    this.allowCredentials = allowCredentials;
  }
}
