package pl.seniordeveloper.platform.testing.arch;

import static com.tngtech.archunit.lang.syntax.ArchRuleDefinition.classes;
import static com.tngtech.archunit.lang.syntax.ArchRuleDefinition.methods;

import com.tngtech.archunit.base.DescribedPredicate;
import com.tngtech.archunit.core.domain.JavaClass;
import com.tngtech.archunit.core.domain.JavaMethod;
import com.tngtech.archunit.junit.ArchTest;
import com.tngtech.archunit.lang.ArchCondition;
import com.tngtech.archunit.lang.ArchRule;
import com.tngtech.archunit.lang.ConditionEvents;
import com.tngtech.archunit.lang.SimpleConditionEvent;
import com.tngtech.archunit.library.GeneralCodingRules;
import java.util.Set;
import org.junit.jupiter.api.Tag;
import org.junit.platform.commons.support.AnnotationSupport;
import pl.seniordeveloper.platform.testing.PlatformTestTags;

/**
 * Wyselekcjonowany, mały zestaw reguł ArchUnit dla konsumentów Platform; każda reguła to osobne
 * pole, więc da się włączyć wszystkie albo wybrane. Wymaga {@code
 * com.tngtech.archunit:archunit-junit5} na classpath testów (seniordev.spring-modulith-conventions
 * dodaje go sam, inni konsumenci przez {@code libs.archunit.junit5}).
 *
 * <pre>{@code
 * @AnalyzeClasses(packagesOf = MyApplication.class, importOptions = ImportOption.DoNotIncludeJars.class)
 * class ArchitectureTest {
 *   @ArchTest ArchTests platform = ArchTests.in(PlatformArchRules.class);
 * }
 * }</pre>
 *
 * <p>W istniejącym kodzie zamroź naruszenia: {@code
 * FreezingArchRule.freeze(PlatformArchRules.NO_FIELD_INJECTION)} zapisuje je w {@code
 * src/test/resources/archunit_store} i odrzuca tylko nowe — ratchet jak przy pokryciu.
 */
public final class PlatformArchRules {

  private static final Set<String> PLATFORM_CONTAINERS =
      Set.of(
          "pl.seniordeveloper.platform.testing.PlatformPostgresContainer",
          "pl.seniordeveloper.platform.testing.PlatformOllamaContainer");

  /** Logowanie, nie {@code System.out}/{@code System.err}/{@code printStackTrace}. */
  @ArchTest
  public static final ArchRule NO_STANDARD_STREAMS =
      GeneralCodingRules.NO_CLASSES_SHOULD_ACCESS_STANDARD_STREAMS;

  /** SLF4J, nie {@code java.util.logging}. */
  @ArchTest
  public static final ArchRule NO_JAVA_UTIL_LOGGING =
      GeneralCodingRules.NO_CLASSES_SHOULD_USE_JAVA_UTIL_LOGGING;

  /** Konkretne wyjątki zamiast {@code Exception}, {@code RuntimeException} i {@code Throwable}. */
  @ArchTest
  public static final ArchRule NO_GENERIC_EXCEPTIONS =
      GeneralCodingRules.NO_CLASSES_SHOULD_THROW_GENERIC_EXCEPTIONS;

  /** Wstrzykiwanie przez konstruktor, nie przez pole. */
  @ArchTest
  public static final ArchRule NO_FIELD_INJECTION =
      GeneralCodingRules.NO_CLASSES_SHOULD_USE_FIELD_INJECTION;

  /**
   * Proxy Springa nie przechwytuje metod prywatnych, więc {@code @Transactional} na nich nic nie
   * robi.
   */
  @ArchTest
  public static final ArchRule TRANSACTIONAL_METHODS_ARE_NOT_PRIVATE =
      methods()
          .that()
          .areAnnotatedWith("org.springframework.transaction.annotation.Transactional")
          .should()
          .notBePrivate()
          .allowEmptyShould(true)
          .because(
              "Spring's proxies never intercept a private method, so its transaction is silently missing");

  /**
   * Kontroler zwraca DTO, nie encję JPA: encja w odpowiedzi wiąże API ze schematem i gubi leniwe
   * relacje.
   */
  @ArchTest
  public static final ArchRule CONTROLLERS_DO_NOT_RETURN_ENTITIES =
      methods()
          .that()
          .areDeclaredInClassesThat()
          .areAnnotatedWith("org.springframework.web.bind.annotation.RestController")
          .and()
          .arePublic()
          .should(notReturnAnEntity())
          .allowEmptyShould(true);

  /**
   * Klasa, która używa kontenera Platform, niesie tag integracyjny — statyczny odpowiednik
   * strażnika w runtime.
   */
  @ArchTest
  public static final ArchRule CONTAINER_TESTS_ARE_TAGGED_INTEGRATION =
      classes()
          .that(useAPlatformContainer())
          .and()
          .areNotAnnotations()
          .should(beTaggedIntegration())
          .allowEmptyShould(true);

  private PlatformArchRules() {}

  private static ArchCondition<JavaMethod> notReturnAnEntity() {
    return new ArchCondition<>("not return a JPA @Entity") {
      @Override
      public void check(JavaMethod method, ConditionEvents events) {
        boolean entity =
            method.getReturnType().getAllInvolvedRawTypes().stream()
                .anyMatch(type -> type.isAnnotatedWith("jakarta.persistence.Entity"));
        if (entity) {
          events.add(
              SimpleConditionEvent.violated(
                  method, method.getFullName() + " returns a JPA @Entity; return a DTO instead"));
        }
      }
    };
  }

  private static DescribedPredicate<JavaClass> useAPlatformContainer() {
    return DescribedPredicate.describe(
        "use a Platform Testcontainers configuration",
        javaClass ->
            javaClass.getDirectDependenciesFromSelf().stream()
                .anyMatch(
                    dependency ->
                        PLATFORM_CONTAINERS.contains(dependency.getTargetClass().getFullName())));
  }

  private static ArchCondition<JavaClass> beTaggedIntegration() {
    return new ArchCondition<>("be tagged " + PlatformTestTags.INTEGRATION) {
      @Override
      public void check(JavaClass javaClass, ConditionEvents events) {
        boolean tagged =
            AnnotationSupport.findRepeatableAnnotations(javaClass.reflect(), Tag.class).stream()
                .anyMatch(tag -> PlatformTestTags.INTEGRATION.equals(tag.value()));
        if (!tagged) {
          events.add(
              SimpleConditionEvent.violated(
                  javaClass,
                  javaClass.getName()
                      + " uses a Platform container without the integration tag;"
                      + " annotate it with @IntegrationTest or @PostgresIntegrationTest"));
        }
      }
    };
  }
}
