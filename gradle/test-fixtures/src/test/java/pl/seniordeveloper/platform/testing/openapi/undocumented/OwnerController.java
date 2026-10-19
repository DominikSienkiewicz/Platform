package pl.seniordeveloper.platform.testing.openapi.undocumented;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
class OwnerController {

  @GetMapping("/owners")
  String owners() {
    return "owners";
  }

  @RequestMapping("/owners/any")
  String anyMethod() {
    return "any";
  }
}
