package pl.seniordeveloper.platform.testing;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.modulith.core.ApplicationModules;
import pl.seniordeveloper.platform.testing.modulith.fixture.FixtureApplication;

class ModulithDocumentationTest {

  @TempDir Path folder;

  private AbstractModulithDocumentationTest documentationOf(Class<?> application, Path output) {
    return new AbstractModulithDocumentationTest() {
      @Override
      protected Class<?> applicationClass() {
        return application;
      }

      @Override
      protected Path outputFolder() {
        return output;
      }

      // Aplikacja-atrapa żyje w źródłach testów, które domyślny skan Modulitha pomija.
      @Override
      protected ApplicationModules modules() {
        return ApplicationModules.of(application, location -> true);
      }
    };
  }

  @Test
  void writesTheComponentDiagramAndOneDiagramPerModule() throws IOException {
    documentationOf(FixtureApplication.class, folder).writesModuleDocumentation();

    assertThat(folder.resolve("components.puml")).isRegularFile();
    assertThat(Files.readString(folder.resolve("components.puml"))).contains("Orders", "Billing");
    assertThat(folder.resolve("module-orders.puml")).isRegularFile();
    assertThat(folder.resolve("module-billing.puml")).isRegularFile();
  }

  @Test
  void writesToTheGradleBuildDirectoryByDefault() {
    var documentation =
        new AbstractModulithDocumentationTest() {
          @Override
          protected Class<?> applicationClass() {
            return FixtureApplication.class;
          }
        };

    assertThat(documentation.outputFolder()).isEqualTo(Path.of("build", "spring-modulith-docs"));
  }
}
