package pl.seniordeveloper.platform.testing.arch.fixture.violating;

import org.springframework.beans.factory.annotation.Autowired;

public class FieldInjected {
  @Autowired private Object dependency;

  public Object dependency() {
    return dependency;
  }
}
