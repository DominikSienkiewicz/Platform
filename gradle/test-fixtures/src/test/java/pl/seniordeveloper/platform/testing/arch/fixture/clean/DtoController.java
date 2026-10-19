package pl.seniordeveloper.platform.testing.arch.fixture.clean;

import org.springframework.web.bind.annotation.RestController;

@RestController
public class DtoController {
  public OrderDto order() {
    return new OrderDto("1");
  }
}
