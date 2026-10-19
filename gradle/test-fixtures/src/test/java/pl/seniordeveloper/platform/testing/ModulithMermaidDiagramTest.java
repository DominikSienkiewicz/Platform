package pl.seniordeveloper.platform.testing;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.modulith.core.ApplicationModules;
import pl.seniordeveloper.platform.testing.modulith.events.EventsFixtureApplication;
import pl.seniordeveloper.platform.testing.modulith.fixture.FixtureApplication;

class ModulithMermaidDiagramTest {

  @TempDir Path folder;

  // Aplikacje-atrapy żyją w źródłach testów, które domyślny skan Modulitha pomija.
  private static ApplicationModules modulesOf(Class<?> application) {
    return ApplicationModules.of(application, location -> true);
  }

  private static String lines(String... lines) {
    return String.join("\n", lines) + "\n";
  }

  @Test
  void drawsOneNodePerModuleAndAPlainDependencyAsDependsOn() {
    assertThat(ModulithMermaidDiagram.render(modulesOf(FixtureApplication.class)))
        .isEqualTo(
            lines(
                "flowchart LR",
                "    module_billing[\"Billing\"]",
                "    module_orders[\"Orders\"]",
                "    module_orders -->|depends on| module_billing"));
  }

  @Test
  void labelsAnInjectionAndAnEventListenerAndDropsTheGenericDependency() {
    assertThat(ModulithMermaidDiagram.render(modulesOf(EventsFixtureApplication.class)))
        .isEqualTo(
            lines(
                "flowchart LR",
                "    module_shipping[\"Shipping\"]",
                "    module_tracking[\"Live #quot;parcel#quot; tracking\"]",
                "    module_tracking -->|uses| module_shipping",
                "    module_tracking -->|listens to| module_shipping"));
  }

  @Test
  void theDocumentationTestWritesTheDiagramNextToThePlantUml() throws IOException {
    var output = folder.resolve("docs");
    new AbstractModulithDocumentationTest() {
      @Override
      protected Class<?> applicationClass() {
        return EventsFixtureApplication.class;
      }

      @Override
      protected Path outputFolder() {
        return output;
      }

      @Override
      protected ApplicationModules modules() {
        return modulesOf(EventsFixtureApplication.class);
      }
    }.writesModuleDocumentation();

    assertThat(output.resolve("components.puml")).isRegularFile();
    assertThat(Files.readString(output.resolve(ModulithMermaidDiagram.FILE_NAME)))
        .isEqualTo(ModulithMermaidDiagram.render(modulesOf(EventsFixtureApplication.class)));
  }
}
