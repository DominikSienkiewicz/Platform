package pl.seniordeveloper.platform.testing;

import static org.junit.jupiter.api.Assertions.assertTrue;

import java.io.IOException;
import java.lang.reflect.Method;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.TreeSet;
import java.util.stream.Collectors;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.config.BeanDefinition;
import org.springframework.context.annotation.ClassPathScanningCandidateComponentProvider;
import org.springframework.core.MethodIntrospector;
import org.springframework.core.io.support.PathMatchingResourcePatternResolver;
import org.springframework.core.type.filter.AnnotationTypeFilter;
import org.springframework.util.ClassUtils;
import org.springframework.web.bind.annotation.RequestMethod;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.servlet.mvc.method.RequestMappingInfo;
import org.springframework.web.servlet.mvc.method.annotation.RequestMappingHandlerMapping;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;
import tools.jackson.databind.json.JsonMapper;
import tools.jackson.dataformat.yaml.YAMLMapper;

/**
 * Wspólny strażnik kontraktu OpenAPI w modelu contract-first (Decyzja 30): commitowany, ręcznie
 * pisany spec jest umową, a ten test pilnuje, żeby mappingi Spring MVC aplikacji i spec opisywały
 * te same operacje, w obie strony. Uogólnienie {@code OpenApiPathCoverageTest} z Azimutha;
 * Docker-free.
 *
 * <p>Zgłasza: operację z kontrolera, której nie ma w specu ({@code missing from OpenAPI}), operację
 * ze specu bez kontrolera ({@code stale in OpenAPI}), operację bez {@code operationId} albo bez
 * {@code responses}, zduplikowany {@code operationId}, mapping bez jawnej metody HTTP oraz
 * nierozwiązany lokalny {@code $ref}. Ścieżki zaczynające się od {@link #ignoredPathPrefixes()} nie
 * są porównywane po żadnej stronie.
 *
 * <p>Konsument (spec JSON albo YAML; YAML wymaga {@code
 * tools.jackson.dataformat:jackson-dataformat-yaml} na classpath testów, JSON {@code
 * tools.jackson.core:jackson-databind}, oba z BOM-u Boota):
 *
 * <pre>{@code
 * class OpenApiContractTest extends AbstractOpenApiContractTest {
 *   protected Path specPath() { return Path.of("contract/openapi.json"); }
 *   protected String basePackage() { return "pl.seniordeveloper.azimuth"; }
 * }
 * }</pre>
 */
public abstract class AbstractOpenApiContractTest {

  private static final Set<String> HTTP_METHODS =
      Set.of("get", "put", "post", "delete", "options", "head", "patch", "trace");

  /**
   * Ścieżka commitowanego specu, względem katalogu roboczego testu (moduł Gradle).
   *
   * @return plik {@code .json}, {@code .yaml} albo {@code .yml}
   */
  protected abstract Path specPath();

  /**
   * Pakiet skanowany w poszukiwaniu {@code @RestController} aplikacji.
   *
   * @return pakiet bazowy, np. {@code pl.seniordeveloper.azimuth}
   */
  protected abstract String basePackage();

  /**
   * Prefiksy ścieżek pomijanych po obu stronach: endpointy frameworka, których spec nie opisuje.
   *
   * @return domyślnie {@code /actuator} i {@code /error}
   */
  protected Set<String> ignoredPathPrefixes() {
    return Set.of("/actuator", "/error");
  }

  // protected (nie package-private), by podklasa konsumenta w innym pakiecie odziedziczyła @Test.
  @Test
  @DisplayName(
      "The committed OpenAPI spec and the Spring MVC mappings describe the same operations")
  protected void specMatchesTheControllers() throws IOException {
    List<String> drift =
        drift(
            readSpec(specPath()),
            implementedOperations(basePackage(), getClass().getClassLoader()),
            ignoredPathPrefixes());
    assertTrue(drift.isEmpty(), "OpenAPI drift:\n  " + String.join("\n  ", drift));
  }

  static JsonNode readSpec(Path spec) throws IOException {
    String name = spec.getFileName().toString().toLowerCase(Locale.ROOT);
    ObjectMapper mapper =
        name.endsWith(".yaml") || name.endsWith(".yml") ? new YAMLMapper() : new JsonMapper();
    return mapper.readTree(Files.readString(spec));
  }

  static Implemented implementedOperations(String basePackage, ClassLoader loader) {
    var scanner = new ClassPathScanningCandidateComponentProvider(false);
    scanner.setResourceLoader(new PathMatchingResourcePatternResolver(loader));
    scanner.addIncludeFilter(new AnnotationTypeFilter(RestController.class));
    Set<Operation> operations = new HashSet<>();
    List<String> problems = new ArrayList<>();
    scanner.findCandidateComponents(basePackage).stream()
        .map(BeanDefinition::getBeanClassName)
        .filter(Objects::nonNull)
        .map(name -> ClassUtils.resolveClassName(name, loader))
        .forEach(controller -> collect(controller, operations, problems));
    return new Implemented(Set.copyOf(operations), List.copyOf(problems));
  }

  private static void collect(
      Class<?> controller, Set<Operation> operations, List<String> problems) {
    var reader = new MappingReader();
    Map<Method, RequestMappingInfo> mappings =
        MethodIntrospector.selectMethods(
            controller,
            (MethodIntrospector.MetadataLookup<RequestMappingInfo>)
                method -> reader.readMapping(method, controller));
    mappings.forEach(
        (method, info) -> {
          Set<RequestMethod> methods = info.getMethodsCondition().getMethods();
          if (methods.isEmpty()) {
            problems.add(
                controller.getName() + "#" + method.getName() + " has no explicit HTTP method");
            return;
          }
          info.getPatternValues()
              .forEach(
                  path ->
                      methods.forEach(
                          m ->
                              operations.add(
                                  new Operation(m.name().toLowerCase(Locale.ROOT), path))));
        });
  }

  static List<String> drift(JsonNode spec, Implemented implemented, Set<String> ignoredPrefixes) {
    List<String> drift = new ArrayList<>(implemented.problems());
    Set<Operation> documented = new HashSet<>();
    JsonNode paths = spec.path("paths");
    if (!paths.isObject()) {
      drift.add("OpenAPI paths object is missing");
    } else {
      Map<String, Operation> operationIds = new HashMap<>();
      paths
          .properties()
          .forEach(
              path ->
                  path.getValue().properties().stream()
                      .filter(entry -> HTTP_METHODS.contains(entry.getKey()))
                      .forEach(
                          entry -> {
                            Operation operation = new Operation(entry.getKey(), path.getKey());
                            documented.add(operation);
                            checkOperation(operation, entry.getValue(), operationIds, drift);
                          }));
    }
    checkReferences(spec, spec, drift);
    Set<Operation> implementedOperations =
        withoutIgnored(implemented.operations(), ignoredPrefixes);
    Set<Operation> documentedOperations = withoutIgnored(documented, ignoredPrefixes);
    sortedDifference(implementedOperations, documentedOperations)
        .forEach(operation -> drift.add("missing from OpenAPI: " + operation));
    sortedDifference(documentedOperations, implementedOperations)
        .forEach(operation -> drift.add("stale in OpenAPI: " + operation));
    return drift;
  }

  private static void checkOperation(
      Operation operation, JsonNode node, Map<String, Operation> operationIds, List<String> drift) {
    if (!node.isObject()) {
      drift.add(operation + " is not an object");
      return;
    }
    String operationId = node.path("operationId").asString("");
    if (operationId.isBlank()) {
      drift.add(operation + " has no operationId");
    } else {
      Operation previous = operationIds.put(operationId, operation);
      if (previous != null) {
        drift.add("duplicate operationId " + operationId + ": " + previous + " and " + operation);
      }
    }
    if (!node.path("responses").isObject() || node.path("responses").isEmpty()) {
      drift.add(operation + " has no responses");
    }
  }

  private static void checkReferences(JsonNode root, JsonNode node, List<String> drift) {
    if (node.isObject()) {
      JsonNode reference = node.get("$ref");
      if (reference != null) {
        String value = reference.asString("");
        if (!value.startsWith("#/")) {
          drift.add("unsupported non-local OpenAPI reference: " + value);
        } else if (root.at(value.substring(1)).isMissingNode()) {
          drift.add("unresolved OpenAPI reference: " + value);
        }
      }
      node.properties().forEach(entry -> checkReferences(root, entry.getValue(), drift));
    } else if (node.isArray()) {
      node.values().forEach(child -> checkReferences(root, child, drift));
    }
  }

  private static Set<Operation> withoutIgnored(Set<Operation> operations, Set<String> prefixes) {
    return operations.stream()
        .filter(operation -> prefixes.stream().noneMatch(operation.path()::startsWith))
        .collect(Collectors.toCollection(HashSet::new));
  }

  private static Set<Operation> sortedDifference(Set<Operation> left, Set<Operation> right) {
    Set<Operation> difference =
        new TreeSet<>(Comparator.comparing(Operation::path).thenComparing(Operation::method));
    difference.addAll(left);
    difference.removeAll(right);
    return difference;
  }

  record Operation(String method, String path) {
    @Override
    public String toString() {
      return method.toUpperCase(Locale.ROOT) + " " + path;
    }
  }

  record Implemented(Set<Operation> operations, List<String> problems) {}

  // getMappingForMethod jest chroniony; podklasa czyta mapping bez kontekstu Springa.
  private static final class MappingReader extends RequestMappingHandlerMapping {
    RequestMappingInfo readMapping(Method method, Class<?> controller) {
      return getMappingForMethod(method, controller);
    }
  }
}
