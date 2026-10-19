package pl.seniordeveloper.platform.web;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class PlatformProblemDetailsExceptionHandlerTest {

  @Test
  void pointersFollowRfc6901() {
    assertThat(PlatformProblemDetailsExceptionHandler.pointer("name")).isEqualTo("#/name");
    assertThat(PlatformProblemDetailsExceptionHandler.pointer("items[0].quantity"))
        .isEqualTo("#/items/0/quantity");
    assertThat(PlatformProblemDetailsExceptionHandler.pointer("a/b~c")).isEqualTo("#/a~1b~0c");
    assertThat(PlatformProblemDetailsExceptionHandler.pointer("")).isEqualTo("#");
  }

  @Test
  void theDetailCountsTheFields() {
    assertThat(PlatformProblemDetailsExceptionHandler.validationDetail(1))
        .isEqualTo("Validation failed for 1 field.");
    assertThat(PlatformProblemDetailsExceptionHandler.validationDetail(3))
        .isEqualTo("Validation failed for 3 fields.");
  }
}
