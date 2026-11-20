package pl.seniordeveloper.platform.testing.arch;

import static org.assertj.core.api.Assertions.assertThat;
import static org.junit.platform.engine.discovery.DiscoverySelectors.selectClass;

import com.tngtech.archunit.junit.AnalyzeClasses;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import java.util.stream.Collectors;
import java.util.stream.Stream;
import org.junit.jupiter.api.Test;
import org.junit.platform.engine.TestExecutionResult;
import org.junit.platform.engine.TestExecutionResult.Status;
import org.junit.platform.engine.discovery.ClassSelector;
import org.junit.platform.launcher.EngineFilter;
import org.junit.platform.launcher.TestExecutionListener;
import org.junit.platform.launcher.TestIdentifier;
import org.junit.platform.launcher.core.LauncherDiscoveryRequestBuilder;
import org.junit.platform.launcher.core.LauncherFactory;

/**
 * Podklasy {@link AbstractArchitectureTest} biegną tu przez silnik ArchUnit JUnit 5, tak jak u
 * konsumenta, więc test sprawdza też, że silnik znajduje składowe {@code @ArchTest} odziedziczone
 * po klasie abstrakcyjnej. Same podklasy są wyłączone z zadania {@code test} w build.gradle.kts, bo
 * część z nich narusza reguły z definicji.
 */
class AbstractArchitectureTestTest {

  private static final String LAYOUT = "pl.seniordeveloper.platform.testing.arch.layout.";

  private static final Set<String> HEXAGON =
      Set.of(
          "domainIsFreeOfFrameworks",
          "domainDependsOnNothingOutsideItself",
          "applicationReachesAdaptersThroughPorts",
          "outboundAdaptersDoNotDependOnInboundAdapters");

  private static final String STANDARD_STREAMS = "PlatformArchRules > NO_STANDARD_STREAMS";

  private static final Set<String> PLATFORM =
      Stream.of(
              "NO_STANDARD_STREAMS",
              "NO_JAVA_UTIL_LOGGING",
              "NO_GENERIC_EXCEPTIONS",
              "NO_FIELD_INJECTION",
              "TRANSACTIONAL_METHODS_ARE_NOT_PRIVATE",
              "CONTROLLERS_DO_NOT_RETURN_ENTITIES",
              "CONTAINER_TESTS_ARE_TAGGED_INTEGRATION")
          .map(rule -> "PlatformArchRules > " + rule)
          .collect(Collectors.toSet());

  @Test
  void theEngineRunsTheInheritedRulesAndTheCanonLayoutPassesThem() {
    Map<String, TestExecutionResult> results = run(Canon.class);

    assertThat(results.keySet()).containsExactlyInAnyOrderElementsOf(union(PLATFORM, HEXAGON));
    assertThat(results.values()).allMatch(result -> result.getStatus() == Status.SUCCESSFUL);
  }

  @Test
  void aDomainOnSpringFailsTheFrameworkRule() {
    Map<String, TestExecutionResult> results = run(DomainOnSpring.class);

    assertThat(failed(results)).containsExactly("domainIsFreeOfFrameworks");
    assertThat(message(results, "domainIsFreeOfFrameworks"))
        .contains("the domain stays free of frameworks", "org.springframework");
  }

  @Test
  void aDomainOnAnAdapterFailsTheDomainIsolationRule() {
    Map<String, TestExecutionResult> results = run(DomainOnAdapter.class);

    assertThat(failed(results)).containsExactly("domainDependsOnNothingOutsideItself");
    assertThat(message(results, "domainDependsOnNothingOutsideItself"))
        .contains("the domain depends on nothing outside itself", "InvoiceTable");
  }

  @Test
  void anApplicationOnAnAdapterFailsThePortRule() {
    Map<String, TestExecutionResult> results = run(ApplicationOnAdapter.class);

    assertThat(failed(results)).containsExactly("applicationReachesAdaptersThroughPorts");
    assertThat(message(results, "applicationReachesAdaptersThroughPorts"))
        .contains("the application reaches adapters only through its ports", "InvoiceTable");
  }

  @Test
  void anOutboundAdapterOnAnInboundAdapterFailsTheAdapterDirectionRule() {
    Map<String, TestExecutionResult> results = run(OutboundOnInbound.class);

    assertThat(failed(results)).containsExactly("outboundAdaptersDoNotDependOnInboundAdapters");
    assertThat(message(results, "outboundAdaptersDoNotDependOnInboundAdapters"))
        .contains("an outbound adapter never calls an inbound adapter", "InvoiceEndpoint");
  }

  @Test
  void theHexagonSwitchedOffSkipsTheLayerRulesButKeepsThePlatformRules() {
    Map<String, TestExecutionResult> withHexagon = run(FlatWithHexagon.class);
    Map<String, TestExecutionResult> withoutHexagon = run(FlatWithoutHexagon.class);

    assertThat(failed(withHexagon))
        .containsExactlyInAnyOrder(STANDARD_STREAMS, "domainDependsOnNothingOutsideItself");
    assertThat(failed(withoutHexagon)).containsExactly(STANDARD_STREAMS);
    assertThat(withStatus(withoutHexagon, Status.ABORTED))
        .containsExactlyInAnyOrderElementsOf(HEXAGON);
    assertThat(message(withoutHexagon, "domainDependsOnNothingOutsideItself"))
        .contains("hexagonal() returns false");
  }

  @Test
  void overriddenPackageNamesAreHonoured() {
    assertThat(failed(run(RenamedLayers.class)))
        .containsExactlyInAnyOrder(
            "domainDependsOnNothingOutsideItself",
            "applicationReachesAdaptersThroughPorts",
            "outboundAdaptersDoNotDependOnInboundAdapters");
    assertThat(failed(run(RenamedLayersUnderCanonNames.class))).isEmpty();
  }

  @Test
  void anInboundAdapterMayDependOnAnOutboundAdapter() {
    Map<String, TestExecutionResult> results = run(InboundOnOutbound.class);

    assertThat(results).hasSize(PLATFORM.size() + HEXAGON.size());
    assertThat(results.values()).allMatch(result -> result.getStatus() == Status.SUCCESSFUL);
  }

  @Test
  void aConsumerStyleSubclassInAnotherPackageRunsEveryInheritedRule() {
    Map<String, TestExecutionResult> results =
        run(selectClass("pl.seniordeveloper.platform.testing.archconsumer.CanonArchitectureTest"));

    assertThat(results.keySet()).containsExactlyInAnyOrderElementsOf(union(PLATFORM, HEXAGON));
    assertThat(results.values()).allMatch(result -> result.getStatus() == Status.SUCCESSFUL);
  }

  @Test
  void anEmptyLayerIsNotAViolation() {
    Map<String, TestExecutionResult> results = run(OnlyADomain.class);

    assertThat(results).hasSize(PLATFORM.size() + HEXAGON.size());
    assertThat(results.values()).allMatch(result -> result.getStatus() == Status.SUCCESSFUL);
  }

  private static Map<String, TestExecutionResult> run(Class<?> testClass) {
    return run(selectClass(testClass));
  }

  private static Map<String, TestExecutionResult> run(ClassSelector selector) {
    Map<String, TestExecutionResult> results = new TreeMap<>();
    var request =
        LauncherDiscoveryRequestBuilder.request()
            .selectors(selector)
            .filters(EngineFilter.includeEngines("archunit"))
            .build();
    LauncherFactory.create()
        .execute(
            request,
            new TestExecutionListener() {
              @Override
              public void executionFinished(TestIdentifier test, TestExecutionResult result) {
                if (test.isTest()) {
                  results.put(test.getDisplayName(), result);
                }
              }
            });
    return results;
  }

  private static Set<String> failed(Map<String, TestExecutionResult> results) {
    return withStatus(results, Status.FAILED);
  }

  private static Set<String> withStatus(Map<String, TestExecutionResult> results, Status status) {
    return results.entrySet().stream()
        .filter(entry -> entry.getValue().getStatus() == status)
        .map(Map.Entry::getKey)
        .collect(Collectors.toSet());
  }

  private static String message(Map<String, TestExecutionResult> results, String test) {
    return results.get(test).getThrowable().map(Throwable::getMessage).orElse("");
  }

  private static Set<String> union(Set<String> first, Set<String> second) {
    return Stream.concat(first.stream(), second.stream()).collect(Collectors.toSet());
  }

  @AnalyzeClasses(packages = LAYOUT + "canon")
  static class Canon extends AbstractArchitectureTest {}

  @AnalyzeClasses(packages = LAYOUT + "domainframework")
  static class DomainOnSpring extends AbstractArchitectureTest {}

  @AnalyzeClasses(packages = LAYOUT + "domainadapter")
  static class DomainOnAdapter extends AbstractArchitectureTest {}

  @AnalyzeClasses(packages = LAYOUT + "applicationadapter")
  static class ApplicationOnAdapter extends AbstractArchitectureTest {}

  @AnalyzeClasses(packages = LAYOUT + "adapterdirection")
  static class OutboundOnInbound extends AbstractArchitectureTest {}

  @AnalyzeClasses(packages = LAYOUT + "inboundonoutbound")
  static class InboundOnOutbound extends AbstractArchitectureTest {}

  @AnalyzeClasses(packages = LAYOUT + "flat")
  static class FlatWithHexagon extends AbstractArchitectureTest {}

  @AnalyzeClasses(packages = LAYOUT + "flat")
  static class FlatWithoutHexagon extends AbstractArchitectureTest {
    @Override
    protected boolean hexagonal() {
      return false;
    }
  }

  @AnalyzeClasses(packages = LAYOUT + "renamed")
  static class RenamedLayersUnderCanonNames extends AbstractArchitectureTest {}

  @AnalyzeClasses(packages = LAYOUT + "renamed")
  static class RenamedLayers extends AbstractArchitectureTest {
    @Override
    protected String domainPackages() {
      return "..core..";
    }

    @Override
    protected String applicationPackages() {
      return "..usecase..";
    }

    @Override
    protected String adapterPackages() {
      return "..infra..";
    }

    @Override
    protected String inboundAdapterPackages() {
      return "..infra.inbound..";
    }

    @Override
    protected String outboundAdapterPackages() {
      return "..infra.outbound..";
    }
  }

  @AnalyzeClasses(packages = LAYOUT + "partial")
  static class OnlyADomain extends AbstractArchitectureTest {}
}
