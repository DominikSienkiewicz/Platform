package pl.seniordeveloper.platform.web;

import static org.assertj.core.api.Assertions.assertThat;

import jakarta.servlet.Filter;
import jakarta.validation.Valid;
import jakarta.validation.Validator;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Positive;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Locale;
import java.util.Objects;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.slf4j.MDC;
import org.springframework.boot.SpringBootConfiguration;
import org.springframework.boot.WebApplicationType;
import org.springframework.boot.autoconfigure.EnableAutoConfiguration;
import org.springframework.boot.builder.SpringApplicationBuilder;
import org.springframework.boot.web.server.context.WebServerApplicationContext;
import org.springframework.context.ConfigurableApplicationContext;
import org.springframework.context.annotation.Bean;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

/**
 * Kontrakt błędów na prawdziwym serwerze: ciało 400 z walidacji równa się złotemu {@code
 * contracts/problem-detail.json}, który parsuje też test api-client, a 404, 409 i 500 mają ten sam
 * kształt.
 */
class PlatformProblemDetailsContractTest {

  private static final JsonMapper JSON = JsonMapper.builder().build();
  private static Locale previous;
  private static ConfigurableApplicationContext context;
  private final HttpClient http = HttpClient.newHttpClient();

  @BeforeAll
  static void start() {
    previous = Locale.getDefault();
    Locale.setDefault(Locale.ENGLISH);
    context =
        new SpringApplicationBuilder(OrdersApplication.class)
            .web(WebApplicationType.SERVLET)
            .run("--server.port=0", "--spring.main.banner-mode=off");
  }

  @AfterAll
  static void stop() {
    context.close();
    Locale.setDefault(previous);
  }

  @Test
  void aValidationFailureAnswersWithTheGoldenProblem() throws Exception {
    HttpResponse<String> response = post("/orders", "{\"name\":\"\",\"items\":[{\"quantity\":0}]}");

    assertThat(response.statusCode()).isEqualTo(400);
    assertThat(response.headers().firstValue("Content-Type")).hasValue("application/problem+json");
    assertThat(JSON.readTree(response.body())).isEqualTo(golden());
  }

  @Test
  void aDataConflictAnswers409WithoutTheDatabaseMessage() throws Exception {
    JsonNode problem = problem(get("/orders/conflict"), 409);

    assertThat(problem.get("detail").asString())
        .isEqualTo(PlatformProblemDetailsExceptionHandler.CONFLICT);
    assertThat(problem.toString()).doesNotContain("duplicate key");
  }

  @Test
  void anUnexpectedFailureAnswers500WithoutItsMessage() throws Exception {
    JsonNode problem = problem(get("/orders/boom"), 500);

    assertThat(problem.get("detail").asString())
        .isEqualTo(PlatformProblemDetailsExceptionHandler.UNEXPECTED);
    assertThat(problem.get("message").asString())
        .isEqualTo(PlatformProblemDetailsExceptionHandler.UNEXPECTED);
    assertThat(problem.toString()).doesNotContain("secret");
  }

  @Test
  void aConstraintViolationAnswers400WithItsErrors() throws Exception {
    JsonNode problem = problem(get("/orders/constraint"), 400);

    assertThat(problem.get("errors").get(0).get("pointer").asString()).isEqualTo("#/name");
    assertThat(problem.get("errors").get(0).get("detail").asString())
        .isEqualTo("must not be blank");
  }

  @Test
  void springErrorsKeepTheShapeAndCarryTheTraceId() throws Exception {
    HttpResponse<String> response =
        http.send(
            request("/missing").header("X-Trace", "4bf92f3577b34da6a3ce929d0e0e4736").GET().build(),
            HttpResponse.BodyHandlers.ofString());
    JsonNode problem = problem(response, 404);

    assertThat(problem.get("traceId").asString()).isEqualTo("4bf92f3577b34da6a3ce929d0e0e4736");
    assertThat(problem.get("message").asString()).isEqualTo(problem.get("detail").asString());
  }

  private JsonNode golden() throws Exception {
    return JSON.readTree(
        Files.readString(
            Path.of(System.getProperty("platform.contracts.dir"), "problem-detail.json")));
  }

  private JsonNode problem(HttpResponse<String> response, int status) {
    assertThat(response.statusCode()).isEqualTo(status);
    assertThat(response.headers().firstValue("Content-Type")).hasValue("application/problem+json");
    JsonNode problem = JSON.readTree(response.body());
    assertThat(problem.get("status").asInt()).isEqualTo(status);
    return problem;
  }

  private HttpResponse<String> get(String path) throws Exception {
    return http.send(request(path).GET().build(), HttpResponse.BodyHandlers.ofString());
  }

  private HttpResponse<String> post(String path, String json) throws Exception {
    return http.send(
        request(path)
            .header("Content-Type", "application/json")
            .POST(HttpRequest.BodyPublishers.ofString(json))
            .build(),
        HttpResponse.BodyHandlers.ofString());
  }

  private static HttpRequest.Builder request(String path) {
    int port =
        Objects.requireNonNull(((WebServerApplicationContext) context).getWebServer()).getPort();
    return HttpRequest.newBuilder(URI.create("http://localhost:" + port + path))
        .header("Accept-Language", "en");
  }

  record Item(@Positive int quantity) {}

  record Order(@NotBlank String name, List<@Valid Item> items) {}

  @RestController
  static class OrdersController {

    private final Validator validator;

    OrdersController(Validator validator) {
      this.validator = validator;
    }

    @PostMapping("/orders")
    Order create(@Valid @RequestBody Order order) {
      return order;
    }

    @GetMapping("/orders/conflict")
    Order conflict() {
      throw new DataIntegrityViolationException("duplicate key value violates unique constraint");
    }

    @GetMapping("/orders/boom")
    Order boom() {
      throw new IllegalStateException("secret connection string");
    }

    @GetMapping("/orders/constraint")
    Order constraint() {
      throw new jakarta.validation.ConstraintViolationException(
          validator.validate(new Order(" ", List.of())));
    }
  }

  @SpringBootConfiguration(proxyBeanMethods = false)
  @EnableAutoConfiguration
  static class OrdersApplication {

    @Bean
    OrdersController ordersController(Validator validator) {
      return new OrdersController(validator);
    }

    // Jak Micrometer Tracing: traceId w MDC na czas żądania.
    @Bean
    Filter traceIdFilter() {
      return (request, response, chain) -> {
        String traceId = ((jakarta.servlet.http.HttpServletRequest) request).getHeader("X-Trace");
        if (traceId != null) {
          MDC.put("traceId", traceId);
        }
        try {
          chain.doFilter(request, response);
        } finally {
          MDC.remove("traceId");
        }
      };
    }
  }
}
