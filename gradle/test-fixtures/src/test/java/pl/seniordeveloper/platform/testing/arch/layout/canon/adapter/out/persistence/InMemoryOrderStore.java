package pl.seniordeveloper.platform.testing.arch.layout.canon.adapter.out.persistence;

import java.util.HashMap;
import java.util.Map;
import java.util.Optional;
import pl.seniordeveloper.platform.testing.arch.layout.canon.application.port.out.OrderStore;
import pl.seniordeveloper.platform.testing.arch.layout.canon.application.port.query.OrderView;
import pl.seniordeveloper.platform.testing.arch.layout.canon.domain.Order;

public class InMemoryOrderStore implements OrderStore, OrderView {
  private final Map<String, Order> orders = new HashMap<>();

  @Override
  public void save(Order order) {
    orders.put(order.id(), order);
  }

  @Override
  public Optional<Order> find(String id) {
    return Optional.ofNullable(orders.get(id));
  }
}
