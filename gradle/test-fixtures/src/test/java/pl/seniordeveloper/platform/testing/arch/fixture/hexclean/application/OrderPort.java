package pl.seniordeveloper.platform.testing.arch.fixture.hexclean.application;

import pl.seniordeveloper.platform.testing.arch.fixture.hexclean.domain.Order;

public interface OrderPort {
  void save(Order order);
}
