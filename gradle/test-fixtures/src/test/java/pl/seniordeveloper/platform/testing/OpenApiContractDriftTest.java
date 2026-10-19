package pl.seniordeveloper.platform.testing;

import static org.assertj.core.api.Assertions.assertThat;

import java.nio.file.Path;
import java.util.Set;
import org.junit.jupiter.api.Test;

class OpenApiContractDriftTest {

  private static final Set<String> IGNORED = Set.of("/actuator", "/error");
  private static final ClassLoader LOADER = OpenApiContractDriftTest.class.getClassLoader();

  private static java.util.List<String> drift(String spec, String basePackage) throws Exception {
    return AbstractOpenApiContractTest.drift(
        AbstractOpenApiContractTest.readSpec(Path.of("src/test/resources/openapi", spec)),
        AbstractOpenApiContractTest.implementedOperations(basePackage, LOADER),
        IGNORED);
  }

  @Test
  void aYamlSpecThatMatchesTheControllersHasNoDrift() throws Exception {
    assertThat(drift("pets.yaml", "pl.seniordeveloper.platform.testing.openapi.documented"))
        .isEmpty();
  }

  @Test
  void aJsonSpecIsReadToo() throws Exception {
    assertThat(drift("pets.json", "pl.seniordeveloper.platform.testing.openapi.documented"))
        .isEmpty();
  }

  @Test
  void anUndocumentedMappingAndOneWithoutAnHttpMethodAreReported() throws Exception {
    assertThat(drift("pets.yaml", "pl.seniordeveloper.platform.testing.openapi"))
        .contains("missing from OpenAPI: GET /owners")
        .anyMatch(line -> line.endsWith("OwnerController#anyMethod has no explicit HTTP method"));
  }

  @Test
  void aStaleOperationAndBrokenEntriesAreReported() throws Exception {
    assertThat(drift("drifted.yaml", "pl.seniordeveloper.platform.testing.openapi.documented"))
        .contains(
            "stale in OpenAPI: DELETE /pets/{id}",
            "POST /pets has no operationId",
            "DELETE /pets/{id} has no responses",
            "duplicate operationId getPet: GET /pets/{id} and DELETE /pets/{id}",
            "unresolved OpenAPI reference: #/components/schemas/Missing");
  }

  @Test
  void ignoredPrefixesAreNotComparedOnEitherSide() throws Exception {
    assertThat(drift("pets.yaml", "pl.seniordeveloper.platform.testing.openapi.documented"))
        .noneMatch(line -> line.contains("/actuator"));
  }
}
