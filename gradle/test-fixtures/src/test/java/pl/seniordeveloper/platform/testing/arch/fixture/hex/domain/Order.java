package pl.seniordeveloper.platform.testing.arch.fixture.hex.domain;

import org.springframework.stereotype.Component;
import pl.seniordeveloper.platform.testing.arch.fixture.hex.adapter.OrderRepository;

@Component
public class Order {
  private final OrderRepository repository = new OrderRepository();

  public OrderRepository repository() {
    return repository;
  }
}
