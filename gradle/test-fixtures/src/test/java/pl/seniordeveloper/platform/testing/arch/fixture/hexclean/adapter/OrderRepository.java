package pl.seniordeveloper.platform.testing.arch.fixture.hexclean.adapter;

import pl.seniordeveloper.platform.testing.arch.fixture.hexclean.application.OrderPort;
import pl.seniordeveloper.platform.testing.arch.fixture.hexclean.domain.Order;

public class OrderRepository implements OrderPort {
  @Override
  public void save(Order order) {
    // Treść bez znaczenia: reguły heksagonalne sprawdzają tylko kierunek zależności adaptera.
  }
}
