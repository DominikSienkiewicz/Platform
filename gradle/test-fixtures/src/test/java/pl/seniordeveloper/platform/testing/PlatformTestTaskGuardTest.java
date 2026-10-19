package pl.seniordeveloper.platform.testing;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.io.ByteArrayOutputStream;
import java.io.PrintStream;
import java.nio.charset.StandardCharsets;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/** Faza fail strażnika kontenerów (N-CAP-8, ADR-0019): fail domyślnie, warn tylko na życzenie. */
class PlatformTestTaskGuardTest {

  private static final String FIX =
      "Testcontainers used in the unit 'test' task (PlatformSharedPostgresContainer): annotate the"
          + " test class with @IntegrationTest or @PostgresIntegrationTest";

  private String originalTask;
  private String originalMode;

  @BeforeEach
  void rememberTheGuardProperties() {
    originalTask = System.getProperty(PlatformTestTaskGuard.TASK_PROPERTY);
    originalMode = System.getProperty(PlatformTestTaskGuard.MODE_PROPERTY);
    System.setProperty(PlatformTestTaskGuard.TASK_PROPERTY, "test");
    System.clearProperty(PlatformTestTaskGuard.MODE_PROPERTY);
  }

  @AfterEach
  void restoreTheGuardProperties() {
    restore(PlatformTestTaskGuard.TASK_PROPERTY, originalTask);
    restore(PlatformTestTaskGuard.MODE_PROPERTY, originalMode);
  }

  private static void restore(String name, String value) {
    if (value == null) {
      System.clearProperty(name);
    } else {
      System.setProperty(name, value);
    }
  }

  private static String stderrOf(Runnable action) {
    PrintStream original = System.err;
    ByteArrayOutputStream captured = new ByteArrayOutputStream();
    System.setErr(new PrintStream(captured, true, StandardCharsets.UTF_8));
    try {
      action.run();
    } finally {
      System.setErr(original);
    }
    return captured.toString(StandardCharsets.UTF_8);
  }

  @Test
  void aContainerInTheUnitTestTaskFailsByDefaultBeforeItStarts() {
    assertThatThrownBy(
            () -> new PlatformSharedPostgresContainer().platformSharedPostgresProperties())
        .isInstanceOf(IllegalStateException.class)
        .hasMessage(FIX);
  }

  @Test
  void aBlankModeKeepsTheFailDefault() {
    System.setProperty(PlatformTestTaskGuard.MODE_PROPERTY, " ");

    assertThatThrownBy(
            () -> PlatformTestTaskGuard.requireIntegrationTask("PlatformSharedPostgresContainer"))
        .isInstanceOf(IllegalStateException.class)
        .hasMessage(FIX);
  }

  @Test
  void theWarnOptOutPrintsTheFixAndTheOptOutInsteadOfFailing() {
    System.setProperty(PlatformTestTaskGuard.MODE_PROPERTY, "warn");

    String stderr =
        stderrOf(
            () ->
                assertThatCode(
                        () ->
                            PlatformTestTaskGuard.requireIntegrationTask(
                                "PlatformSharedPostgresContainer"))
                    .doesNotThrowAnyException());

    assertThat(stderr)
        .contains("WARNING: " + FIX)
        .contains("platform.test.guard=warn keeps this a warning; without it the test fails.");
  }

  @Test
  void anUnknownModeFailsAndNamesTheAcceptedModes() {
    System.setProperty(PlatformTestTaskGuard.MODE_PROPERTY, "wran");

    assertThatThrownBy(
            () -> PlatformTestTaskGuard.requireIntegrationTask("PlatformSharedPostgresContainer"))
        .isInstanceOf(IllegalStateException.class)
        .hasMessage(
            FIX
                + ". platform.test.guard=wran is not a guard mode: use warn to keep a warning, or"
                + " fail");
  }

  @Test
  void theModesAreCaseSensitiveSoAnUppercaseOptOutStillFails() {
    System.setProperty(PlatformTestTaskGuard.MODE_PROPERTY, "WARN");

    assertThatThrownBy(
            () -> PlatformTestTaskGuard.requireIntegrationTask("PlatformSharedPostgresContainer"))
        .isInstanceOf(IllegalStateException.class)
        .hasMessageContaining("platform.test.guard=WARN is not a guard mode");
  }

  @Test
  void theModeIsIrrelevantOutsideTheUnitTestTask() {
    System.setProperty(PlatformTestTaskGuard.TASK_PROPERTY, "integrationTest");
    assertThatCode(() -> PlatformTestTaskGuard.requireIntegrationTask("container"))
        .doesNotThrowAnyException();

    System.setProperty(PlatformTestTaskGuard.MODE_PROPERTY, "wran");
    assertThatCode(() -> PlatformTestTaskGuard.requireIntegrationTask("container"))
        .doesNotThrowAnyException();
  }
}
