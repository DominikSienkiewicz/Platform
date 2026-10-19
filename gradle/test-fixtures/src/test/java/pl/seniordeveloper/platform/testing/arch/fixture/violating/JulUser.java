package pl.seniordeveloper.platform.testing.arch.fixture.violating;

import java.util.logging.Logger;

public class JulUser {
  private static final Logger LOG = Logger.getLogger("jul");

  public void report() {
    LOG.info("done");
  }
}
