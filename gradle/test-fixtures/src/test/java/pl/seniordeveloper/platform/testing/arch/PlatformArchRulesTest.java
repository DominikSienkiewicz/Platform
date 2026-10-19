package pl.seniordeveloper.platform.testing.arch;

import static org.assertj.core.api.Assertions.assertThat;

import com.tngtech.archunit.core.domain.JavaClasses;
import com.tngtech.archunit.core.importer.ClassFileImporter;
import com.tngtech.archunit.lang.ArchRule;
import com.tngtech.archunit.lang.EvaluationResult;
import java.util.stream.Stream;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.Arguments;
import org.junit.jupiter.params.provider.MethodSource;

class PlatformArchRulesTest {

  private static final String FIXTURE = "pl.seniordeveloper.platform.testing.arch.fixture";
  private static final JavaClasses VIOLATING =
      new ClassFileImporter().importPackages(FIXTURE + ".violating");
  private static final JavaClasses CLEAN =
      new ClassFileImporter().importPackages(FIXTURE + ".clean");

  static Stream<Arguments> rules() {
    return Stream.of(
        Arguments.of("NO_STANDARD_STREAMS", PlatformArchRules.NO_STANDARD_STREAMS, "StreamUser"),
        Arguments.of("NO_JAVA_UTIL_LOGGING", PlatformArchRules.NO_JAVA_UTIL_LOGGING, "JulUser"),
        Arguments.of(
            "NO_GENERIC_EXCEPTIONS", PlatformArchRules.NO_GENERIC_EXCEPTIONS, "GenericThrower"),
        Arguments.of("NO_FIELD_INJECTION", PlatformArchRules.NO_FIELD_INJECTION, "FieldInjected"),
        Arguments.of(
            "TRANSACTIONAL_METHODS_ARE_NOT_PRIVATE",
            PlatformArchRules.TRANSACTIONAL_METHODS_ARE_NOT_PRIVATE,
            "PrivateTransactional.work()"),
        Arguments.of(
            "CONTROLLERS_DO_NOT_RETURN_ENTITIES",
            PlatformArchRules.CONTROLLERS_DO_NOT_RETURN_ENTITIES,
            "EntityController.orders() returns a JPA @Entity"),
        Arguments.of(
            "CONTAINER_TESTS_ARE_TAGGED_INTEGRATION",
            PlatformArchRules.CONTAINER_TESTS_ARE_TAGGED_INTEGRATION,
            "UntaggedContainerTest uses a Platform container without the integration tag"));
  }

  @ParameterizedTest(name = "{0} flags the violating fixture")
  @MethodSource("rules")
  void eachRuleFlagsItsViolation(String name, ArchRule rule, String expected) {
    EvaluationResult result = rule.evaluate(VIOLATING);

    assertThat(result.hasViolation()).isTrue();
    assertThat(result.getFailureReport().getDetails())
        .anyMatch(detail -> detail.contains(expected));
  }

  @ParameterizedTest(name = "{0} accepts the clean fixture")
  @MethodSource("rules")
  void eachRuleAcceptsCleanCode(String name, ArchRule rule, String expected) {
    assertThat(rule.evaluate(CLEAN).hasViolation()).isFalse();
  }

  @org.junit.jupiter.api.Test
  void hexagonalRulesKeepTheDomainAndTheApplicationAwayFromAdapters() {
    JavaClasses violating = new ClassFileImporter().importPackages(FIXTURE + ".hex");
    JavaClasses clean = new ClassFileImporter().importPackages(FIXTURE + ".hexclean");

    var rules = HexagonalRules.of("..domain..", "..application..", "..adapter..");

    assertThat(rules).hasSize(3);
    assertThat(rules)
        .allSatisfy(rule -> assertThat(rule.evaluate(violating).hasViolation()).isTrue());
    assertThat(rules).allSatisfy(rule -> assertThat(rule.evaluate(clean).hasViolation()).isFalse());
  }
}
