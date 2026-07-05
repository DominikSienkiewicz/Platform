package pl.seniordeveloper.platform.security;

import java.util.List;
import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Konfiguracja łańcucha bezpieczeństwa — starter NIE zamraża postawy (wszystko sterowane property).
 * Domyślnie: {@code AUTHENTICATED} + httpBasic + CSRF on, ścieżki health/info przepuszczone (bramka
 * deployu). BookOfStyling ({@code permit-all} + stateless + csrf off) i SkillSprintPlus (domyślne)
 * różniły się tylko wartościami — teraz to property.
 */
@ConfigurationProperties(prefix = "platform.security")
public class PlatformSecurityProperties {

  public enum Mode {
    /** Reszta żądań wymaga uwierzytelnienia (domyślne — bezpieczne). */
    AUTHENTICATED,
    /** Wszystko {@code permitAll} (np. BFF/stateless za bramą, dev). */
    PERMIT_ALL
  }

  private Mode mode = Mode.AUTHENTICATED;
  private boolean stateless = false;
  private boolean csrf = true;
  private boolean httpBasic = true;
  private List<String> permittedPaths =
      List.of("/actuator/health", "/actuator/health/**", "/actuator/info");

  public Mode getMode() {
    return mode;
  }

  public void setMode(Mode mode) {
    this.mode = mode;
  }

  public boolean isStateless() {
    return stateless;
  }

  public void setStateless(boolean stateless) {
    this.stateless = stateless;
  }

  public boolean isCsrf() {
    return csrf;
  }

  public void setCsrf(boolean csrf) {
    this.csrf = csrf;
  }

  public boolean isHttpBasic() {
    return httpBasic;
  }

  public void setHttpBasic(boolean httpBasic) {
    this.httpBasic = httpBasic;
  }

  public List<String> getPermittedPaths() {
    return permittedPaths;
  }

  public void setPermittedPaths(List<String> permittedPaths) {
    this.permittedPaths = permittedPaths;
  }
}
