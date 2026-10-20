package pl.seniordeveloper.platform.testing;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Comparator;
import java.util.EnumSet;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import org.springframework.modulith.core.ApplicationModule;
import org.springframework.modulith.core.ApplicationModules;
import org.springframework.modulith.core.DependencyType;

/**
 * Diagram modułów Spring Modulith w Mermaid ({@value #FILE_NAME}), który GitHub renderuje w bloku
 * {@code ```mermaid}, w przeciwieństwie do PlantUML z {@code Documenter}. {@code flowchart LR}:
 * węzeł na każdy moduł aplikacji i krawędź na każdą zależność między modułami, z etykietami jak w
 * diagramie komponentów Documentera ({@code uses}, {@code listens to}, {@code depends on}); samo
 * {@code depends on} znika, gdy ta sama para modułów ma zależność bardziej konkretną. Kolejność
 * węzłów i krawędzi wynika z identyfikatorów modułów, więc ten sam kod daje bajt w bajt ten sam
 * plik.
 */
final class ModulithMermaidDiagram {

  static final String FILE_NAME = "modules.mmd";

  private static final String INDENT = "    ";

  private ModulithMermaidDiagram() {}

  static String render(ApplicationModules modules) {
    var sorted =
        modules.stream().sorted(Comparator.comparing(ModulithMermaidDiagram::identifier)).toList();
    var diagram = new StringBuilder("flowchart LR\n");
    for (var module : sorted) {
      diagram
          .append(INDENT)
          .append(nodeId(module))
          .append("[\"")
          .append(label(module))
          .append("\"]\n");
    }
    for (var module : sorted) {
      for (var edge : relationsOf(module, modules).entrySet()) {
        for (var relation : edge.getValue()) {
          diagram
              .append(INDENT)
              .append(nodeId(module))
              .append(" -->|")
              .append(relation.label)
              .append("| ")
              .append(edge.getKey())
              .append('\n');
        }
      }
    }
    return diagram.toString();
  }

  static void write(ApplicationModules modules, Path folder) {
    try {
      Files.createDirectories(folder);
      Files.writeString(folder.resolve(FILE_NAME), render(modules), StandardCharsets.UTF_8);
    } catch (IOException e) {
      throw new UncheckedIOException("Cannot write " + folder.resolve(FILE_NAME), e);
    }
  }

  // Klucz = węzeł docelowy; TreeMap i EnumSet ustalają kolejność krawędzi niezależnie od skanu.
  private static Map<String, Set<Relation>> relationsOf(
      ApplicationModule module, ApplicationModules modules) {
    Map<String, Set<Relation>> relations = new TreeMap<>();
    module.getDirectDependencies(modules).stream()
        .forEach(
            dependency ->
                relations
                    .computeIfAbsent(
                        nodeId(dependency.getTargetModule()),
                        target -> EnumSet.noneOf(Relation.class))
                    .add(Relation.of(dependency.getDependencyType())));
    for (var kinds : relations.values()) {
      if (kinds.size() > 1) {
        kinds.remove(Relation.DEPENDS_ON);
      }
    }
    return relations;
  }

  private static String identifier(ApplicationModule module) {
    return module.getIdentifier().toString();
  }

  // Encja Mermaid zamiast cudzysłowu, który zamknąłby etykietę węzła.
  private static String label(ApplicationModule module) {
    return module.getDisplayName().replace("\"", "#quot;");
  }

  // Prefiks chroni przed słowami kluczowymi Mermaid (np. moduł `end` albo `style` psuje flowchart).
  private static String nodeId(ApplicationModule module) {
    return "module_" + identifier(module).replaceAll("\\W", "_");
  }

  private enum Relation {
    USES("uses"),
    LISTENS_TO("listens to"),
    DEPENDS_ON("depends on");

    private final String label;

    Relation(String label) {
      this.label = label;
    }

    static Relation of(DependencyType type) {
      return switch (type) {
        case USES_COMPONENT -> USES;
        case EVENT_LISTENER -> LISTENS_TO;
        default -> DEPENDS_ON;
      };
    }
  }
}
