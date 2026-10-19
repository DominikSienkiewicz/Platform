package pl.seniordeveloper.platform.testing.arch.fixture.violating;

import org.springframework.transaction.annotation.Transactional;

public class PrivateTransactional {
  public void run() {
    work();
  }

  @Transactional
  private void work() {}
}
