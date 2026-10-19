package pl.seniordeveloper.platform.testing;

import java.nio.file.Path;

/** Jak u konsumenta: podklasa dziedziczy @Test i porównuje swój spec z kontrolerami. */
class SampleOpenApiContractTest extends AbstractOpenApiContractTest {

  @Override
  protected Path specPath() {
    return Path.of("src/test/resources/openapi/pets.yaml");
  }

  @Override
  protected String basePackage() {
    return "pl.seniordeveloper.platform.testing.openapi.documented";
  }
}
