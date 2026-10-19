package pl.seniordeveloper.platform.testing.arch.fixture.clean;

public class CleanService {
  private final OrderDto template;

  public CleanService(OrderDto template) {
    this.template = template;
  }

  public OrderDto template() {
    return template;
  }
}
