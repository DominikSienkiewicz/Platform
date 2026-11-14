package pl.seniordeveloper.platform.web;

import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.jspecify.annotations.Nullable;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.HttpStatusCode;
import org.springframework.http.ProblemDetail;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.BindingResult;
import org.springframework.validation.FieldError;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ControllerAdvice;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.context.request.WebRequest;
import org.springframework.web.servlet.mvc.method.annotation.ResponseEntityExceptionHandler;

/**
 * Jeden kształt błędu REST w całej Platformie: RFC 9457 {@code application/problem+json}, który
 * czyta {@code @dominiksienkiewicz/api-client} ({@code ApiError.problem}); złoty przykład: {@code
 * contracts/problem-detail.json}.
 *
 * <ul>
 *   <li>Wyjątki Spring MVC — jak {@link ResponseEntityExceptionHandler}; walidacja {@code @Valid}
 *       (400) dostaje {@code errors[]} z {@code pointer} (JSON Pointer pola) i {@code detail}.
 *   <li>{@code jakarta.validation.ConstraintViolationException} — 400 z {@code errors[]}.
 *   <li>Konflikty spring-dao (integralność danych, optymistyczne i pesymistyczne blokady) — 409 bez
 *       treści SQL.
 *   <li>Każdy inny wyjątek — 500 z ogólnym opisem; szczegóły trafiają tylko do logu.
 * </ul>
 *
 * <p>Każda odpowiedź dostaje {@code traceId} z MDC, gdy tracing go ustawił, a w linii 1.x także
 * {@code message} równe {@code detail} dla klientów czytających stary kształt. Walidacja i
 * spring-dao są opcjonalne, więc ich wyjątki rozpoznaje się po nazwie klasy — starter nie wymaga
 * żadnej z tych bibliotek.
 */
@ControllerAdvice
public class PlatformProblemDetailsExceptionHandler extends ResponseEntityExceptionHandler {

  static final String UNEXPECTED = "An unexpected error occurred.";
  static final String CONFLICT = "The request conflicts with the current state of the resource.";
  private static final Logger LOGGER =
      LoggerFactory.getLogger(PlatformProblemDetailsExceptionHandler.class);
  private static final Set<String> CONFLICTS =
      Set.of(
          "org.springframework.dao.DataIntegrityViolationException",
          "org.springframework.dao.OptimisticLockingFailureException",
          "org.springframework.dao.PessimisticLockingFailureException");
  private static final String CONSTRAINT_VIOLATION =
      "jakarta.validation.ConstraintViolationException";

  private final boolean legacyMessage;

  /**
   * Handler z wybranym kształtem zgodności.
   *
   * @param legacyMessage czy kopiować {@code detail} do {@code message}
   */
  public PlatformProblemDetailsExceptionHandler(boolean legacyMessage) {
    this.legacyMessage = legacyMessage;
  }

  @Override
  protected @Nullable ResponseEntity<Object> handleMethodArgumentNotValid(
      MethodArgumentNotValidException ex,
      HttpHeaders headers,
      HttpStatusCode status,
      WebRequest request) {
    List<Map<String, String>> errors = fieldErrors(ex.getBindingResult());
    ProblemDetail problem =
        ProblemDetail.forStatusAndDetail(status, validationDetail(errors.size()));
    problem.setProperty("errors", errors);
    return handleExceptionInternal(ex, problem, headers, status, request);
  }

  /**
   * Wszystko, czego nie obsługuje {@link ResponseEntityExceptionHandler}.
   *
   * @param ex wyjątek z kontrolera
   * @param request bieżące żądanie
   * @return 400, 409 albo 500 jako Problem Details
   */
  @ExceptionHandler(Exception.class)
  public @Nullable ResponseEntity<Object> handleUnmapped(Exception ex, WebRequest request) {
    ProblemDetail problem;
    if (isA(ex, CONSTRAINT_VIOLATION)) {
      List<Map<String, String>> errors = ConstraintViolations.errors(ex);
      problem =
          ProblemDetail.forStatusAndDetail(HttpStatus.BAD_REQUEST, validationDetail(errors.size()));
      problem.setProperty("errors", errors);
    } else if (CONFLICTS.stream().anyMatch(type -> isA(ex, type))) {
      problem = ProblemDetail.forStatusAndDetail(HttpStatus.CONFLICT, CONFLICT);
    } else {
      LOGGER.error("Unhandled exception, answered with 500", ex);
      problem = ProblemDetail.forStatusAndDetail(HttpStatus.INTERNAL_SERVER_ERROR, UNEXPECTED);
    }
    return handleExceptionInternal(
        ex, problem, new HttpHeaders(), HttpStatusCode.valueOf(problem.getStatus()), request);
  }

  @Override
  protected ResponseEntity<Object> createResponseEntity(
      @Nullable Object body, HttpHeaders headers, HttpStatusCode statusCode, WebRequest request) {
    if (body instanceof ProblemDetail problem) {
      enrich(problem);
    }
    return super.createResponseEntity(body, headers, statusCode, request);
  }

  private void enrich(ProblemDetail problem) {
    String traceId = MDC.get("traceId");
    if (traceId != null && !traceId.isBlank()) {
      problem.setProperty("traceId", traceId);
    }
    if (legacyMessage) {
      String message = problem.getDetail() != null ? problem.getDetail() : problem.getTitle();
      if (message != null) {
        problem.setProperty("message", message);
      }
    }
  }

  static String validationDetail(int errors) {
    return "Validation failed for " + errors + (errors == 1 ? " field." : " fields.");
  }

  static List<Map<String, String>> fieldErrors(BindingResult result) {
    return result.getAllErrors().stream()
        .map(
            error ->
                Map.of(
                    "pointer",
                    error instanceof FieldError field ? pointer(field.getField()) : "#",
                    "detail",
                    String.valueOf(error.getDefaultMessage())))
        .sorted(Comparator.comparing((Map<String, String> error) -> error.get("pointer")))
        .toList();
  }

  /** {@code items[0].quantity} → {@code #/items/0/quantity} (RFC 6901 w fragmencie URI). */
  static String pointer(String path) {
    String segments =
        path.replace("[", ".")
            .replace("]", "")
            .replace("~", "~0")
            .replace("/", "~1")
            .replace('.', '/');
    return segments.isEmpty() ? "#" : "#/" + segments;
  }

  private static boolean isA(Throwable ex, String className) {
    for (Class<?> type = ex.getClass(); type != null; type = type.getSuperclass()) {
      if (type.getName().equals(className)) {
        return true;
      }
    }
    return false;
  }

  /**
   * Odwołuje się do jakarta.validation; ładowana tylko, gdy wyjątek tej biblioteki już istnieje.
   */
  private static final class ConstraintViolations {

    static List<Map<String, String>> errors(Exception ex) {
      return ((jakarta.validation.ConstraintViolationException) ex)
          .getConstraintViolations().stream()
              .map(
                  violation ->
                      Map.of(
                          "pointer",
                          pointer(violation.getPropertyPath().toString()),
                          "detail",
                          String.valueOf(violation.getMessage())))
              .sorted(Comparator.comparing((Map<String, String> error) -> error.get("pointer")))
              .toList();
    }
  }
}
