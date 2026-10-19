package pl.seniordeveloper.platform.security;

import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import org.slf4j.MDC;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.core.AuthenticationException;
import org.springframework.security.web.AuthenticationEntryPoint;
import org.springframework.security.web.access.AccessDeniedHandler;

/**
 * Odpowiedzi 401 i 403 jako {@code application/problem+json} (RFC 9457) w kształcie web-startera:
 * {@code title}, {@code status}, {@code detail}, {@code instance}, {@code message} (linia 1.x) i
 * {@code traceId} z MDC. Nagłówek {@code WWW-Authenticate} ustawia {@code challenge} (Bearer w
 * trybie JWT) albo realm Basic; ciało pisze zawsze ta klasa, bo {@code
 * BasicAuthenticationEntryPoint} woła {@code sendError} i zamyka odpowiedź przed treścią.
 */
final class PlatformSecurityProblems implements AuthenticationEntryPoint, AccessDeniedHandler {

  static final String UNAUTHENTICATED = "Authentication is required to access this resource.";
  static final String DENIED = "Access to this resource is denied.";

  private final String basicRealm;
  private final AuthenticationEntryPoint challenge;
  private final AccessDeniedHandler deniedChallenge;

  private PlatformSecurityProblems(
      String basicRealm, AuthenticationEntryPoint challenge, AccessDeniedHandler deniedChallenge) {
    this.basicRealm = basicRealm;
    this.challenge = challenge;
    this.deniedChallenge = deniedChallenge;
  }

  /** Bez wyzwania: 401 bez {@code WWW-Authenticate}. */
  static PlatformSecurityProblems plain() {
    return new PlatformSecurityProblems(null, null, null);
  }

  /** HTTP Basic: {@code WWW-Authenticate: Basic realm="Realm"}, jak domyślny Spring Security. */
  static PlatformSecurityProblems basic() {
    return new PlatformSecurityProblems("Realm", null, null);
  }

  /** Resource server: nagłówki i status z handlerów Bearer (RFC 6750), ciało stąd. */
  static PlatformSecurityProblems bearer(
      AuthenticationEntryPoint challenge, AccessDeniedHandler deniedChallenge) {
    return new PlatformSecurityProblems(null, challenge, deniedChallenge);
  }

  @Override
  public void commence(
      HttpServletRequest request, HttpServletResponse response, AuthenticationException exception)
      throws IOException, ServletException {
    if (challenge != null) {
      challenge.commence(request, response, exception);
    } else {
      response.setStatus(HttpStatus.UNAUTHORIZED.value());
      if (basicRealm != null) {
        response.setHeader(HttpHeaders.WWW_AUTHENTICATE, "Basic realm=\"" + basicRealm + "\"");
      }
    }
    write(request, response, UNAUTHENTICATED);
  }

  @Override
  public void handle(
      HttpServletRequest request, HttpServletResponse response, AccessDeniedException exception)
      throws IOException, ServletException {
    if (deniedChallenge != null) {
      deniedChallenge.handle(request, response, exception);
    } else {
      response.setStatus(HttpStatus.FORBIDDEN.value());
    }
    write(request, response, DENIED);
  }

  private static void write(HttpServletRequest request, HttpServletResponse response, String detail)
      throws IOException {
    if (response.isCommitted()) {
      return;
    }
    HttpStatus status = HttpStatus.resolve(response.getStatus());
    String title = status != null ? status.getReasonPhrase() : "HTTP " + response.getStatus();
    StringBuilder json = new StringBuilder("{");
    json.append("\"title\":").append(quote(title));
    json.append(",\"status\":").append(response.getStatus());
    json.append(",\"detail\":").append(quote(detail));
    json.append(",\"instance\":").append(quote(request.getRequestURI()));
    json.append(",\"message\":").append(quote(detail));
    String traceId = MDC.get("traceId");
    if (traceId != null && !traceId.isBlank()) {
      json.append(",\"traceId\":").append(quote(traceId));
    }
    json.append('}');
    response.setContentType("application/problem+json");
    response.setCharacterEncoding(StandardCharsets.UTF_8.name());
    response.getWriter().write(json.toString());
  }

  static String quote(String value) {
    StringBuilder quoted = new StringBuilder("\"");
    for (char c : value.toCharArray()) {
      switch (c) {
        case '"' -> quoted.append("\\\"");
        case '\\' -> quoted.append("\\\\");
        case '\n' -> quoted.append("\\n");
        case '\r' -> quoted.append("\\r");
        case '\t' -> quoted.append("\\t");
        default -> {
          if (c < 0x20) {
            quoted.append(String.format("\\u%04x", (int) c));
          } else {
            quoted.append(c);
          }
        }
      }
    }
    return quoted.append('"').toString();
  }
}
