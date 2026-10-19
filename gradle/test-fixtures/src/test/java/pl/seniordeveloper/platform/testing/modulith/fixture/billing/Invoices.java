package pl.seniordeveloper.platform.testing.modulith.fixture.billing;

public class Invoices {
  public String invoiceFor(String order) {
    return "invoice:" + order;
  }
}
