package pl.seniordeveloper.platform.observability;

import static org.assertj.core.api.Assertions.assertThat;

import com.jayway.jsonpath.JsonPath;
import java.io.IOException;
import java.nio.file.Path;
import java.util.List;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * Kontrakt {@code requireFeature("tracing")} z docs/reference.md na opublikowanych metadanych:
 * konsument deklaruje starter i wariant osobno, więc wariant niesie tylko exporter, a główny
 * starter go nie wnosi. Gradle 10 odrzuca feature na source secie {@code main}, który publikował
 * główny jar drugi raz.
 */
class PlatformObservabilityTracingVariantTest {

  private static final String EXPORTER = "spring-boot-starter-opentelemetry";

  @Test
  @DisplayName("The tracing variant has its capability and brings the OpenTelemetry starter")
  void theTracingVariantBringsTheExporter() throws IOException {
    for (String variant : List.of("tracingApiElements", "tracingRuntimeElements")) {
      assertThat(read(variant, "capabilities[*].name"))
          .containsExactly("platform-observability-starter-tracing");
      assertThat(read(variant, "dependencies[*].module")).contains(EXPORTER);
    }
  }

  @Test
  @DisplayName("The tracing variant does not publish the main jar a second time")
  void theTracingVariantHasItsOwnJar() throws IOException {
    for (String variant : List.of("tracingApiElements", "tracingRuntimeElements")) {
      assertThat(read(variant, "files[*].name"))
          .singleElement()
          .asString()
          .endsWith("-tracing.jar");
    }
  }

  @Test
  @DisplayName("The main variants of the starter do not bring the OpenTelemetry starter")
  void theMainVariantsDoNotBringTheExporter() throws IOException {
    for (String variant : List.of("apiElements", "runtimeElements")) {
      assertThat(read(variant, "dependencies[*].module")).isNotEmpty().doesNotContain(EXPORTER);
    }
  }

  private static List<String> read(String variant, String path) throws IOException {
    return JsonPath.read(
        Path.of(System.getProperty("platform.moduleMetadata")).toFile(),
        "$.variants[?(@.name == '" + variant + "')]." + path);
  }
}
