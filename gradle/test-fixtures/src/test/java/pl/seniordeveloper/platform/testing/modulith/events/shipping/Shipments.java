package pl.seniordeveloper.platform.testing.modulith.events.shipping;

import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Component;

@Component
public class Shipments {
  private final ApplicationEventPublisher events;

  public Shipments(ApplicationEventPublisher events) {
    this.events = events;
  }

  public void ship(String parcel) {
    events.publishEvent(new ParcelShipped(parcel));
  }
}
