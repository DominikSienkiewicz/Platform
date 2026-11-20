package pl.seniordeveloper.platform.testing.arch.layout.canon.application;

import pl.seniordeveloper.platform.testing.arch.layout.canon.application.port.in.PlaceOrder;
import pl.seniordeveloper.platform.testing.arch.layout.canon.application.port.out.OrderStore;
import pl.seniordeveloper.platform.testing.arch.layout.canon.domain.Order;

public class PlaceOrderService implements PlaceOrder {
  private final OrderStore store;

  public PlaceOrderService(OrderStore store) {
    this.store = store;
  }

  @Override
  public void place(Order order) {
    store.save(order);
  }
}
