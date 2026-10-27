package pl.seniordeveloper.platform.testing.schema.jdbc;

import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * Najmniejsza aplikacja konsumenta z {@code spring-modulith-starter-jdbc}: bez JPA, rejestr
 * publikacji zdarzeń zapisuje przez JDBC do tabeli z szablonów {@code templates/db}.
 */
@SpringBootApplication(proxyBeanMethods = false)
public class JdbcRegistrySampleApplication {}
