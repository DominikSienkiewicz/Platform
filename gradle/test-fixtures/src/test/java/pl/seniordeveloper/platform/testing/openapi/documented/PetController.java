package pl.seniordeveloper.platform.testing.openapi.documented;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/pets")
class PetController {

  @GetMapping("/{id}")
  String pet(@PathVariable String id) {
    return id;
  }

  @PostMapping
  String create() {
    return "created";
  }
}
