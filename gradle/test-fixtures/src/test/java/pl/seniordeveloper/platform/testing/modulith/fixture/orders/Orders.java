package pl.seniordeveloper.platform.testing.modulith.fixture.orders;

import pl.seniordeveloper.platform.testing.modulith.fixture.billing.Invoices;

public class Orders {
  private final Invoices invoices;

  public Orders(Invoices invoices) {
    this.invoices = invoices;
  }

  public String place(String order) {
    return invoices.invoiceFor(order);
  }
}
