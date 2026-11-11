package pl.seniordeveloper.platform.observability;

import io.micrometer.common.KeyValue;
import io.micrometer.observation.Observation;
import io.micrometer.observation.ObservationFilter;
import io.micrometer.observation.transport.Kind;
import io.micrometer.observation.transport.ReceiverContext;
import io.micrometer.tracing.handler.TracingObservationHandler.TracingContext;
import io.micrometer.tracing.otel.bridge.OtelSpan;
import io.opentelemetry.api.trace.StatusCode;

/**
 * Oznacza span serwera HTTP jako {@code ERROR}, gdy odpowiedź jest 5xx, a obserwacja nie zapisała
 * wyjątku: tak każą semantic conventions OpenTelemetry dla spanów serwera, a 4xx zostawiają status
 * nieustawiony. Most Micrometera ustawia status tylko z wyjątku, więc 500 odpisane bez niego
 * (transport MCP, {@code @ExceptionHandler}) zostawało w Tempo bez statusu.
 *
 * <p>5xx rozpoznaje po kluczu {@code outcome=SERVER_ERROR}, który konwencje serwera HTTP Springa
 * (domyślna i OpenTelemetry, servlet i reactive) wyliczają ze statusu odpowiedzi. Status bez opisu,
 * bo powód niesie już atrybut statusu HTTP; wyjątek zostaje przy statusie i opisie, które ustawił
 * most. Filtr, a nie handler: Micrometer woła filtry w {@code stop()} przed {@code onStop}
 * handlerów, więc span jest jeszcze otwarty bez względu na kolejność rejestracji handlerów.
 */
final class ServerErrorSpanStatus implements ObservationFilter {

  private static final String OUTCOME = "outcome";

  private static final String SERVER_ERROR = "SERVER_ERROR";

  @Override
  public Observation.Context map(Observation.Context context) {
    if (isServerErrorWithoutException(context)) {
      TracingContext tracing = context.get(TracingContext.class);
      if (tracing != null && tracing.getSpan() instanceof OtelSpan span) {
        OtelSpan.toOtel(span).setStatus(StatusCode.ERROR);
      }
    }
    return context;
  }

  private static boolean isServerErrorWithoutException(Observation.Context context) {
    if (!(context instanceof ReceiverContext<?> receiver)
        || receiver.getKind() != Kind.SERVER
        || context.getError() != null) {
      return false;
    }
    KeyValue outcome = context.getLowCardinalityKeyValue(OUTCOME);
    return outcome != null && SERVER_ERROR.equals(outcome.getValue());
  }
}
