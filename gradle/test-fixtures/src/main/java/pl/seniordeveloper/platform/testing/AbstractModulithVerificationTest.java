package pl.seniordeveloper.platform.testing;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.modulith.core.ApplicationModules;

/**
 * Wspólna weryfikacja struktury Spring Modulith (brak cykli, brak dostępu do internals innych
 * modułów). Docker-free, szybka — bez tagu integration.
 *
 * <p>Konsument podaje klasę główną aplikacji:
 * <pre>{@code
 * class ModulithVerificationTest extends AbstractModulithVerificationTest {
 *   @Override protected Class<?> applicationClass() { return MyApplication.class; }
 * }
 * }</pre>
 */
public abstract class AbstractModulithVerificationTest {

  /** Klasa główna aplikacji (z adnotacją @SpringBootApplication) — punkt startu skanu modułów. */
  protected abstract Class<?> applicationClass();

  // protected (nie package-private), by podklasa konsumenta w innym pakiecie odziedziczyła @Test.
  @Test
  @DisplayName("Struktura modułów Spring Modulith jest poprawna (verify)")
  protected void verifiesModuleStructure() {
    ApplicationModules.of(applicationClass()).verify();
  }
}
