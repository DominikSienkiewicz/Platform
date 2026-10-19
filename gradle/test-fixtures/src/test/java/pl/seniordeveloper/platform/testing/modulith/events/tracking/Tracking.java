package pl.seniordeveloper.platform.testing.modulith.events.tracking;

import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;
import pl.seniordeveloper.platform.testing.modulith.events.shipping.ParcelShipped;
import pl.seniordeveloper.platform.testing.modulith.events.shipping.Shipments;

// Wstrzyknięcie i nasłuch na jeden moduł: krawędzie uses i listens to, bez ogólnego depends on.
@Component
public class Tracking {
  private final Shipments shipments;
  private String lastParcel = "";

  public Tracking(Shipments shipments) {
    this.shipments = shipments;
  }

  @EventListener
  public void on(ParcelShipped event) {
    lastParcel = event.parcel();
  }

  public void reship() {
    shipments.ship(lastParcel);
  }
}
