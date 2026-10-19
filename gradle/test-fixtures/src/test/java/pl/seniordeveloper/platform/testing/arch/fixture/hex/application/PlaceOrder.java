package pl.seniordeveloper.platform.testing.arch.fixture.hex.application;

import pl.seniordeveloper.platform.testing.arch.fixture.hex.adapter.OrderRepository;

public class PlaceOrder {
  public OrderRepository repository() {
    return new OrderRepository();
  }
}
