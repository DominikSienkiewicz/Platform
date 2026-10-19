package pl.seniordeveloper.platform.testing.arch.fixture.violating;

public class GenericThrower {
  public void fail() {
    throw new RuntimeException("boom");
  }
}
