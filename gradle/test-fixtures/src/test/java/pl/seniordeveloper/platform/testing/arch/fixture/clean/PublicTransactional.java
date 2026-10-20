package pl.seniordeveloper.platform.testing.arch.fixture.clean;

import org.springframework.transaction.annotation.Transactional;

public class PublicTransactional {
  @Transactional
  public void work() {
    // Treść bez znaczenia: reguła sprawdza tylko widoczność metody z @Transactional.
  }
}
