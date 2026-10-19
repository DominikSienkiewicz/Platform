package pl.seniordeveloper.platform.testing.arch.fixture.violating;

import java.util.List;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class EntityController {
  public List<OrderEntity> orders() {
    return List.of();
  }
}
