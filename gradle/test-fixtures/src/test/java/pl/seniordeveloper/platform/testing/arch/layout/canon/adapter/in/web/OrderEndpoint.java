package pl.seniordeveloper.platform.testing.arch.layout.canon.adapter.in.web;

import pl.seniordeveloper.platform.testing.arch.layout.canon.application.port.in.PlaceOrder;
import pl.seniordeveloper.platform.testing.arch.layout.canon.domain.Order;

public class OrderEndpoint {
  private final PlaceOrder placeOrder;

  public OrderEndpoint(PlaceOrder placeOrder) {
    this.placeOrder = placeOrder;
  }

  public void post(String id) {
    placeOrder.place(new Order(id));
  }
}
