package pl.seniordeveloper.platform.testing;

import java.nio.file.Path;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.modulith.core.ApplicationModules;
import org.springframework.modulith.docs.Documenter;

/**
 * Dokumentacja modułów Spring Modulith z tej samej struktury, którą weryfikuje {@link
 * AbstractModulithVerificationTest}: diagramy komponentów C4 w PlantUML ({@code components.puml} i
 * jeden na moduł) oraz kanwy modułów w AsciiDoc, do {@link #outputFolder()} — domyślnie {@code
 * build/spring-modulith-docs}, który backend-ci dołącza jako artefakt. Bez renderowania SVG: ten
 * zostaje przeglądarce PlantUML. Wymaga {@code org.springframework.modulith:spring-modulith-docs}
 * na classpath testów, który {@code spring-modulith-starter-test} już dostarcza.
 *
 * <pre>{@code
 * class ModulithDocumentationTest extends AbstractModulithDocumentationTest {
 *   @Override protected Class<?> applicationClass() { return MyApplication.class; }
 * }
 * }</pre>
 */
public abstract class AbstractModulithDocumentationTest {

  /**
   * Klasa główna aplikacji — punkt startu skanu modułów.
   *
   * @return klasa z adnotacją {@code @SpringBootApplication}
   */
  protected abstract Class<?> applicationClass();

  /**
   * Katalog dokumentacji, względem katalogu roboczego testu (moduł Gradle).
   *
   * @return domyślnie {@code build/spring-modulith-docs}
   */
  protected Path outputFolder() {
    return Path.of("build", "spring-modulith-docs");
  }

  /**
   * Moduły do udokumentowania; nadpisz, żeby zmienić skan (np. {@code ImportOption}).
   *
   * @return moduły aplikacji z {@link #applicationClass()}
   */
  protected ApplicationModules modules() {
    return ApplicationModules.of(applicationClass());
  }

  // protected (nie package-private), by podklasa konsumenta w innym pakiecie odziedziczyła @Test.
  @Test
  @DisplayName("Spring Modulith writes the module diagrams and canvases")
  protected void writesModuleDocumentation() {
    new Documenter(
            modules(), Documenter.Options.defaults().withOutputFolder(outputFolder().toString()))
        .writeDocumentation();
  }
}
