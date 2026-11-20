package pl.seniordeveloper.platform.testing.arch;

import static com.tngtech.archunit.lang.syntax.ArchRuleDefinition.noClasses;

import com.tngtech.archunit.lang.ArchRule;
import java.util.List;

/**
 * Preset architektury heksagonalnej (porty i adaptery), uogólniony z reguł Azimutha: domena nie zna
 * frameworków ani pozostałych warstw, a aplikacja nie zna adapterów — rozmawia z nimi przez porty.
 * Gotowy zestaw z regułami Platform i kanonem pakietów daje {@link AbstractArchitectureTest}.
 *
 * <pre>{@code
 * @ArchTest
 * void hexagonal(JavaClasses classes) {
 *   HexagonalRules.of("..domain..", "..application..", "..adapter..").forEach(rule -> rule.check(classes));
 * }
 * }</pre>
 */
public final class HexagonalRules {

  private HexagonalRules() {}

  /**
   * Reguły dla trzech warstw, podanych jako wzorce pakietów ArchUnit.
   *
   * @param domain pakiety domeny, np. {@code ..domain..}
   * @param application pakiety warstwy aplikacji (porty i przypadki użycia), np. {@code
   *     ..application..}
   * @param adapter pakiety adapterów, np. {@code ..adapter..}
   * @return reguły w kolejności: domena bez frameworków, domena bez warstw zewnętrznych, aplikacja
   *     bez adapterów
   */
  public static List<ArchRule> of(String domain, String application, String adapter) {
    return List.of(
        domainIsFreeOfFrameworks(domain),
        domainDependsOnNothingOutsideItself(domain, application, adapter),
        applicationReachesAdaptersThroughPorts(application, adapter));
  }

  /**
   * Adapter wyjściowy (np. {@code adapter.out}) implementuje port i nie woła adaptera wejściowego
   * (np. {@code adapter.in}); poza {@link #of(String, String, String)}, żeby ta lista zachowała
   * swoje trzy reguły.
   *
   * @param outboundAdapter pakiety adapterów wyjściowych, np. {@code ..adapter.out..}
   * @param inboundAdapter pakiety adapterów wejściowych, np. {@code ..adapter.in..}
   * @return reguła: adaptery wyjściowe nie zależą od wejściowych
   */
  public static ArchRule outboundAdaptersDoNotDependOnInboundAdapters(
      String outboundAdapter, String inboundAdapter) {
    return noClasses()
        .that()
        .resideInAPackage(outboundAdapter)
        .should()
        .dependOnClassesThat()
        .resideInAPackage(inboundAdapter)
        .because("an outbound adapter never calls an inbound adapter");
  }

  static ArchRule domainIsFreeOfFrameworks(String domain) {
    return noClasses()
        .that()
        .resideInAPackage(domain)
        .should()
        .dependOnClassesThat()
        .resideInAnyPackage("org.springframework..", "jakarta.persistence..", "jakarta.servlet..")
        .because("the domain stays free of frameworks");
  }

  static ArchRule domainDependsOnNothingOutsideItself(
      String domain, String application, String adapter) {
    return noClasses()
        .that()
        .resideInAPackage(domain)
        .should()
        .dependOnClassesThat()
        .resideInAnyPackage(application, adapter)
        .because("the domain depends on nothing outside itself");
  }

  static ArchRule applicationReachesAdaptersThroughPorts(String application, String adapter) {
    return noClasses()
        .that()
        .resideInAPackage(application)
        .should()
        .dependOnClassesThat()
        .resideInAPackage(adapter)
        .because("the application reaches adapters only through its ports");
  }
}
