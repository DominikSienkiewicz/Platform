package pl.seniordeveloper.platform.testing;

import java.lang.annotation.Documented;
import java.lang.annotation.ElementType;
import java.lang.annotation.Inherited;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;
import org.junit.jupiter.api.Tag;

/**
 * Test integracyjny: tag {@value PlatformTestTags#INTEGRATION}, więc biegnie w {@code
 * integrationTest}.
 */
@Target({ElementType.TYPE, ElementType.METHOD, ElementType.ANNOTATION_TYPE})
@Retention(RetentionPolicy.RUNTIME)
@Documented
@Inherited
@Tag(PlatformTestTags.INTEGRATION)
public @interface IntegrationTest {}
