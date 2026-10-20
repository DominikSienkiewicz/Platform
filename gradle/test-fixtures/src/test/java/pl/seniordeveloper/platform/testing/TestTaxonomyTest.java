package pl.seniordeveloper.platform.testing;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.util.List;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.junit.platform.commons.support.AnnotationSupport;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;

class TestTaxonomyTest {

  @IntegrationTest
  static class Integration {}

  @ModelTest
  static class Model {}

  @PostgresIntegrationTest
  static class Postgres {}

  @AfterEach
  void clearTheGuardProperties() {
    System.clearProperty(PlatformTestTaskGuard.TASK_PROPERTY);
    System.clearProperty(PlatformTestTaskGuard.MODE_PROPERTY);
  }

  private static List<String> tags(Class<?> type) {
    return AnnotationSupport.findRepeatableAnnotations(type, Tag.class).stream()
        .map(Tag::value)
        .toList();
  }

  @Test
  void theAnnotationsCarryThePlatformTags() {
    assertThat(tags(Integration.class)).containsExactly(PlatformTestTags.INTEGRATION);
    assertThat(tags(Model.class)).containsExactly(PlatformTestTags.MODEL);
    assertThat(tags(Postgres.class)).containsExactly(PlatformTestTags.INTEGRATION);
  }

  @Test
  void postgresIntegrationTestStartsBootOnThePlatformContainer() {
    assertThat(AnnotationSupport.isAnnotated(Postgres.class, SpringBootTest.class)).isTrue();
    assertThat(AnnotationSupport.findAnnotation(Postgres.class, Import.class))
        .hasValueSatisfying(
            imported ->
                assertThat(imported.value())
                    .containsExactly(PlatformSharedPostgresContainer.class));
  }

  @Test
  void aContainerInTheUnitTestTaskFailsWithTheFixWhenTheGuardFails() {
    System.setProperty(PlatformTestTaskGuard.TASK_PROPERTY, "test");
    System.setProperty(PlatformTestTaskGuard.MODE_PROPERTY, "fail");
    var configuration = new PlatformPostgresContainer();

    assertThatThrownBy(configuration::pgvectorContainer)
        .isInstanceOf(IllegalStateException.class)
        .hasMessage(
            "Testcontainers used in the unit 'test' task (PlatformPostgresContainer): annotate the test class"
                + " with @IntegrationTest or @PostgresIntegrationTest");
  }

  @Test
  void aContainerInTheUnitTestTaskOnlyWarnsByDefault() {
    System.setProperty(PlatformTestTaskGuard.TASK_PROPERTY, "test");
    java.io.PrintStream original = System.err;
    java.io.ByteArrayOutputStream captured = new java.io.ByteArrayOutputStream();
    System.setErr(new java.io.PrintStream(captured, true, java.nio.charset.StandardCharsets.UTF_8));
    try {
      assertThatCode(
              () -> PlatformTestTaskGuard.requireIntegrationTask("PlatformPostgresContainer"))
          .doesNotThrowAnyException();
    } finally {
      System.setErr(original);
    }
    assertThat(captured.toString(java.nio.charset.StandardCharsets.UTF_8))
        .contains(
            "WARNING: Testcontainers used in the unit 'test' task (PlatformPostgresContainer)")
        .contains("A later Platform release fails such a test.");
  }

  @Test
  void theGuardAcceptsTheIntegrationTaskAndABuildThatDoesNotNameItsTask() {
    System.setProperty(PlatformTestTaskGuard.TASK_PROPERTY, "integrationTest");
    assertThatCode(() -> PlatformTestTaskGuard.requireIntegrationTask("container"))
        .doesNotThrowAnyException();

    System.clearProperty(PlatformTestTaskGuard.TASK_PROPERTY);
    assertThatCode(() -> PlatformTestTaskGuard.requireIntegrationTask("container"))
        .doesNotThrowAnyException();
  }
}
