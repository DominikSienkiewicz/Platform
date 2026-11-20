package pl.seniordeveloper.platform.testing.arch;

import com.tngtech.archunit.core.domain.JavaClasses;
import com.tngtech.archunit.junit.ArchTest;
import com.tngtech.archunit.junit.ArchTests;
import com.tngtech.archunit.lang.ArchRule;
import org.junit.jupiter.api.Assumptions;

/**
 * Wspólny test architektury konsumenta (ADR-0038): wszystkie reguły {@link PlatformArchRules}, trzy
 * reguły {@link HexagonalRules#of(String, String, String)} i reguła „adapter wyjściowy nie zależy
 * od wejściowego” na kanonie pakietów {@code domain}, {@code application} (porty w {@code
 * application.port..}), {@code adapter.in..} i {@code adapter.out..}. Pusta warstwa nie jest
 * naruszeniem, więc moduł bez adapterów przechodzi. Podklasa wskazuje klasy przez
 * {@code @AnalyzeClasses}, a silnik ArchUnit JUnit 5 uruchamia składowe {@code @ArchTest}
 * odziedziczone po tej klasie. Wymaga {@code com.tngtech.archunit:archunit-junit5} na classpath
 * testów (seniordev.spring-modulith-conventions dodaje go sam).
 *
 * <pre>{@code
 * @AnalyzeClasses(packagesOf = MyApplication.class, importOptions = ImportOption.DoNotIncludeJars.class)
 * class ArchitectureTest extends AbstractArchitectureTest {}
 * }</pre>
 *
 * <p>Moduły płaskie, bez warstw, wyłączają heksagon i zostają przy regułach Platform: reguły
 * heksagonu kończą się wtedy jako pominięte (aborted), a nie zaliczone. Moduły jako osobne projekty
 * Gradle trafiają na classpath testów aplikacji jako jary, więc bez {@code DoNotIncludeJars} —
 * klasy wybiera pakiet.
 *
 * <pre>{@code
 * @AnalyzeClasses(packagesOf = MyApplication.class)
 * class ArchitectureTest extends AbstractArchitectureTest {
 *   @Override protected boolean hexagonal() { return false; }
 * }
 * }</pre>
 */
public abstract class AbstractArchitectureTest {

  @ArchTest final ArchTests platformRules = ArchTests.in(PlatformArchRules.class);

  /** Konstruktor dla podklasy konsumenta. */
  protected AbstractArchitectureTest() {}

  /**
   * Pakiety domeny jako wzorzec ArchUnit.
   *
   * @return domyślnie {@code ..domain..}
   */
  protected String domainPackages() {
    return "..domain..";
  }

  /**
   * Pakiety warstwy aplikacji (przypadki użycia i porty w {@code application.port..}, np. {@code
   * port.in}, {@code port.out}, {@code port.query}).
   *
   * @return domyślnie {@code ..application..}
   */
  protected String applicationPackages() {
    return "..application..";
  }

  /**
   * Wszystkie adaptery, wejściowe i wyjściowe. Wzorce pakietów są niezależne: nadpisanie tej metody
   * nie przesuwa domyślnych {@link #inboundAdapterPackages()} ani {@link
   * #outboundAdapterPackages()}, więc przy innych nazwach adapterów nadpisz wszystkie trzy. Pusta
   * warstwa przechodzi, więc wzorzec, który niczego nie trafia, przechodzi po cichu.
   *
   * @return domyślnie {@code ..adapter..}
   */
  protected String adapterPackages() {
    return "..adapter..";
  }

  /**
   * Adaptery wejściowe (web, CLI, listenery), które wołają porty aplikacji.
   *
   * @return domyślnie {@code ..adapter.in..}
   */
  protected String inboundAdapterPackages() {
    return "..adapter.in..";
  }

  /**
   * Adaptery wyjściowe (baza, klienci HTTP), które implementują porty aplikacji.
   *
   * @return domyślnie {@code ..adapter.out..}
   */
  protected String outboundAdapterPackages() {
    return "..adapter.out..";
  }

  /**
   * Czy sprawdzać heksagon; {@code false} dla modułów płaskich, które mają tylko reguły Platform.
   *
   * @return domyślnie {@code true}
   */
  protected boolean hexagonal() {
    return true;
  }

  @ArchTest
  final void domainIsFreeOfFrameworks(JavaClasses classes) {
    checkHexagon(HexagonalRules.domainIsFreeOfFrameworks(domainPackages()), classes);
  }

  @ArchTest
  final void domainDependsOnNothingOutsideItself(JavaClasses classes) {
    checkHexagon(
        HexagonalRules.domainDependsOnNothingOutsideItself(
            domainPackages(), applicationPackages(), adapterPackages()),
        classes);
  }

  @ArchTest
  final void applicationReachesAdaptersThroughPorts(JavaClasses classes) {
    checkHexagon(
        HexagonalRules.applicationReachesAdaptersThroughPorts(
            applicationPackages(), adapterPackages()),
        classes);
  }

  @ArchTest
  final void outboundAdaptersDoNotDependOnInboundAdapters(JavaClasses classes) {
    checkHexagon(
        HexagonalRules.outboundAdaptersDoNotDependOnInboundAdapters(
            outboundAdapterPackages(), inboundAdapterPackages()),
        classes);
  }

  private void checkHexagon(ArchRule rule, JavaClasses classes) {
    Assumptions.assumeTrue(
        hexagonal(), "the hexagon is switched off: hexagonal() returns false in " + getClass());
    rule.allowEmptyShould(true).check(classes);
  }
}
