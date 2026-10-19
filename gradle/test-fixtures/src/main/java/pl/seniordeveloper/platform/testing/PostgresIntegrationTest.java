package pl.seniordeveloper.platform.testing;

import java.lang.annotation.Documented;
import java.lang.annotation.ElementType;
import java.lang.annotation.Inherited;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;

/**
 * Pełny kontekst Spring Boot na współdzielonym PostgreSQL z {@link PlatformPostgresContainer},
 * otagowany jako {@link IntegrationTest} — zamiast trzech adnotacji, z których brak tagu uruchamiał
 * Dockera w {@code test}.
 */
@Target(ElementType.TYPE)
@Retention(RetentionPolicy.RUNTIME)
@Documented
@Inherited
@IntegrationTest
@SpringBootTest
@Import(PlatformPostgresContainer.class)
public @interface PostgresIntegrationTest {}
