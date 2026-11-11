package pl.seniordeveloper.platform.observability;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatIllegalStateException;

import io.micrometer.observation.Observation;
import io.micrometer.observation.ObservationFilter;
import io.micrometer.observation.ObservationRegistry;
import io.micrometer.observation.transport.Kind;
import io.micrometer.observation.transport.SenderContext;
import io.micrometer.tracing.otel.bridge.OtelSpan;
import io.opentelemetry.api.common.AttributeKey;
import io.opentelemetry.api.trace.SpanKind;
import io.opentelemetry.api.trace.StatusCode;
import io.opentelemetry.context.Context;
import io.opentelemetry.sdk.trace.ReadWriteSpan;
import io.opentelemetry.sdk.trace.ReadableSpan;
import io.opentelemetry.sdk.trace.SpanProcessor;
import io.opentelemetry.sdk.trace.data.SpanData;
import io.opentelemetry.sdk.trace.data.StatusData;
import jakarta.servlet.FilterChain;
import jakarta.servlet.http.HttpServletResponse;
import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.stream.Stream;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.boot.autoconfigure.AutoConfiguration;
import org.springframework.boot.autoconfigure.AutoConfigurations;
import org.springframework.boot.context.annotation.ImportCandidates;
import org.springframework.boot.micrometer.observation.autoconfigure.ObservationAutoConfiguration;
import org.springframework.boot.micrometer.tracing.autoconfigure.MicrometerTracingAutoConfiguration;
import org.springframework.boot.micrometer.tracing.opentelemetry.autoconfigure.OpenTelemetryTracingAutoConfiguration;
import org.springframework.boot.opentelemetry.autoconfigure.OpenTelemetrySdkAutoConfiguration;
import org.springframework.boot.test.context.FilteredClassLoader;
import org.springframework.boot.test.context.assertj.AssertableApplicationContext;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.util.ClassUtils;
import org.springframework.web.filter.ServerHttpObservationFilter;

/**
 * Status spanu serwera HTTP według semantic conventions OpenTelemetry: odpowiedź 5xx to {@code
 * ERROR}, 4xx i sukces zostawiają status nieustawiony. Ćwiczenie 2026-11-10: transport MCP sam
 * odpisuje 500, wyjątek nie dociera do obserwacji, więc TraceQL {@code status = error} nie
 * znajdował żadnego z 25 błędów. Żądanie idzie przez {@link ServerHttpObservationFilter}, jak w
 * aplikacji Spring MVC, na auto-konfiguracjach tracingu Boota i starterze, którego
 * auto-konfiguracje biorą się z {@code AutoConfiguration.imports}, jak u konsumenta.
 */
class ServerErrorSpanStatusTest {

  private static final AttributeKey<String> OUTCOME = AttributeKey.stringKey("outcome");

  private final EndedSpans ended = new EndedSpans();

  private final ApplicationContextRunner runner =
      new ApplicationContextRunner()
          .withConfiguration(AutoConfigurations.of(tracingAutoConfigurations()))
          .withPropertyValues("management.tracing.sampling.probability=1.0")
          .withBean(SpanProcessor.class, () -> ended);

  @Test
  @DisplayName("A 500 the handler writes itself, without an exception, marks the server span ERROR")
  void aServerErrorWithoutAnExceptionMarksTheServerSpanAsAnError() {
    runner.run(
        context -> {
          serve(context, answering(500));

          SpanData span = serverSpan();
          assertThat(span.getAttributes().get(OUTCOME)).isEqualTo("SERVER_ERROR");
          assertThat(span.getStatus()).isEqualTo(StatusData.error());
          assertThat(span.getEvents()).isEmpty();
        });
  }

  @ParameterizedTest(name = "A {0} leaves the status of the server span unset")
  @ValueSource(ints = {200, 404})
  @DisplayName("A success or a client error leaves the status of the server span unset")
  void aSuccessOrAClientErrorLeavesTheStatusUnset(int status) {
    runner.run(
        context -> {
          serve(context, answering(status));

          assertThat(serverSpan().getStatus()).isEqualTo(StatusData.unset());
        });
  }

  @Test
  @DisplayName("A client span is not marked ERROR, even with the outcome SERVER_ERROR")
  void aClientSpanIsNotMarkedAsAnError() {
    runner.run(
        context -> {
          Observation.createNotStarted(
                  "http.client.requests",
                  () -> new SenderContext<>((carrier, key, value) -> {}, Kind.CLIENT),
                  context.getBean(ObservationRegistry.class))
              .lowCardinalityKeyValue("outcome", "SERVER_ERROR")
              .observe(() -> {});

          assertThat(ended.spans)
              .singleElement()
              .satisfies(
                  span -> {
                    assertThat(span.getKind()).isEqualTo(SpanKind.CLIENT);
                    assertThat(span.getStatus().getStatusCode()).isNotEqualTo(StatusCode.ERROR);
                  });
        });
  }

  @Test
  @DisplayName("A thrown exception keeps its ERROR status, its description and its exception event")
  void aThrownExceptionKeepsItsOwnErrorStatus() {
    runner.run(
        context -> {
          assertThatIllegalStateException()
              .isThrownBy(
                  () ->
                      serve(
                          context,
                          (request, response) -> {
                            throw new IllegalStateException("Missing handler for request type");
                          }))
              .withMessage("Missing handler for request type");

          SpanData span = serverSpan();
          assertThat(span.getStatus())
              .isEqualTo(StatusData.create(StatusCode.ERROR, "Missing handler for request type"));
          assertThat(span.getEvents()).extracting("name").containsExactly("exception");
        });
  }

  @Test
  @DisplayName("Without the OpenTelemetry bridge the starter adds no observation filter")
  void withoutTheOpenTelemetryBridgeTheStarterAddsNoFilter() {
    new ApplicationContextRunner()
        .withClassLoader(new FilteredClassLoader(OtelSpan.class))
        .withConfiguration(AutoConfigurations.of(tracingAutoConfigurations()))
        .run(
            context ->
                assertThat(context.getBeansOfType(ObservationFilter.class).values())
                    .noneMatch(
                        filter -> filter.getClass().getName().startsWith(starterPackagePrefix())));
  }

  private static void serve(AssertableApplicationContext context, FilterChain chain)
      throws Exception {
    assertThat(context).hasNotFailed();
    new ServerHttpObservationFilter(context.getBean(ObservationRegistry.class))
        .doFilter(new MockHttpServletRequest("POST", "/mcp"), new MockHttpServletResponse(), chain);
  }

  private static FilterChain answering(int status) {
    return (request, response) -> ((HttpServletResponse) response).setStatus(status);
  }

  private SpanData serverSpan() {
    assertThat(ended.spans)
        .singleElement()
        .extracting(SpanData::getKind)
        .isEqualTo(SpanKind.SERVER);
    return ended.spans.getFirst();
  }

  /**
   * Auto-konfiguracje tracingu Boota, z których aplikacja ma spany serwera, i auto-konfiguracje
   * startera z jego {@code AutoConfiguration.imports}.
   */
  private static Class<?>[] tracingAutoConfigurations() {
    ClassLoader loader = ServerErrorSpanStatusTest.class.getClassLoader();
    Stream<Class<?>> boot =
        Stream.of(
            ObservationAutoConfiguration.class,
            MicrometerTracingAutoConfiguration.class,
            OpenTelemetrySdkAutoConfiguration.class,
            OpenTelemetryTracingAutoConfiguration.class);
    Stream<Class<?>> starter =
        ImportCandidates.load(AutoConfiguration.class, loader).getCandidates().stream()
            .filter(name -> name.startsWith(starterPackagePrefix()))
            .map(name -> ClassUtils.resolveClassName(name, loader));
    return Stream.concat(boot, starter).toArray(Class<?>[]::new);
  }

  private static String starterPackagePrefix() {
    return ServerErrorSpanStatusTest.class.getPackageName() + ".";
  }

  /** Spany zakończone przez SDK OpenTelemetry, w kolejności końca. */
  private static final class EndedSpans implements SpanProcessor {

    private final List<SpanData> spans = new CopyOnWriteArrayList<>();

    @Override
    public void onStart(Context parentContext, ReadWriteSpan span) {}

    @Override
    public boolean isStartRequired() {
      return false;
    }

    @Override
    public void onEnd(ReadableSpan span) {
      spans.add(span.toSpanData());
    }

    @Override
    public boolean isEndRequired() {
      return true;
    }
  }
}
