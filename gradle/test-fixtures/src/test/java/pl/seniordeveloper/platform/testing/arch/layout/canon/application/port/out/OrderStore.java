package pl.seniordeveloper.platform.testing.arch.layout.canon.application.port.out;

import pl.seniordeveloper.platform.testing.arch.layout.canon.domain.Order;

public interface OrderStore {
  void save(Order order);
}
