package pl.seniordeveloper.platform.testing.arch.layout.canon.application.port.query;

import java.util.Optional;
import pl.seniordeveloper.platform.testing.arch.layout.canon.domain.Order;

public interface OrderView {
  Optional<Order> find(String id);
}
