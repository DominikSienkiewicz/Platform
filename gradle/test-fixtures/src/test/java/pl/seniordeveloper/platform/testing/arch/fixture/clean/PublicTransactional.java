package pl.seniordeveloper.platform.testing.arch.fixture.clean;

import org.springframework.transaction.annotation.Transactional;

public class PublicTransactional {
  @Transactional
  public void work() {}
}
