package pl.seniordeveloper.platform.testing.schema;

import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * Najmniejsza aplikacja konsumenta z {@code spring-modulith-starter-jpa}: jedyną encją jest {@code
 * JpaEventPublication} Spring Moduliths, więc walidacja schematu sprawdza dokładnie tabelę z
 * szablonów.
 */
@SpringBootApplication(proxyBeanMethods = false)
public class SchemaSampleApplication {}
