package pl.seniordeveloper.platform.testing;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.junit.jupiter.api.Assumptions.assumeTrue;

import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.opentest4j.AssertionFailedError;
import org.springframework.boot.SpringBootConfiguration;
import org.springframework.boot.WebApplicationType;
import org.springframework.boot.autoconfigure.ImportAutoConfiguration;
import org.springframework.boot.builder.SpringApplicationBuilder;
import org.springframework.boot.jdbc.autoconfigure.DataSourceAutoConfiguration;
import org.springframework.boot.jdbc.autoconfigure.JdbcTemplateAutoConfiguration;
import org.springframework.boot.testcontainers.properties.TestcontainersPropertySourceAutoConfiguration;
import org.springframework.context.ConfigurableApplicationContext;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;
import org.testcontainers.DockerClientFactory;

@IntegrationTest
class SharedPostgresContainerIT {

  @BeforeAll
  static void requireDocker() {
    assumeTrue(DockerClientFactory.instance().isDockerAvailable(), "Docker is not available");
  }

  @Test
  void twoDifferentContextsShareOneEphemeralServerThatOutlivesEitherOfThem() {
    try (ConfigurableApplicationContext second = start(SecondApplication.class)) {
      long firstServer;
      try (ConfigurableApplicationContext first = start(FirstApplication.class)) {
        firstServer = systemIdentifier(first);
        assertThat(systemIdentifier(second)).isEqualTo(firstServer);
        assertThat(jdbc(first).queryForObject("SHOW fsync", String.class)).isEqualTo("off");
        assertThat(AbstractTestcontainersFootprintTest.postgresContainersOfThisSession())
            .hasSize(1);
      }

      assertThat(systemIdentifier(second)).isEqualTo(firstServer);
      assertThat(PlatformSharedPostgresContainer.container().isRunning()).isTrue();
    }
  }

  @Test
  void theFootprintGateNamesTheFixWhenMoreContainersRunThanAllowed() {
    try (ConfigurableApplicationContext context = start(FirstApplication.class)) {
      new AbstractTestcontainersFootprintTest() {}.onePostgresContainerPerJvm();

      AbstractTestcontainersFootprintTest noneAllowed =
          new AbstractTestcontainersFootprintTest() {
            @Override
            protected int maximumPostgresContainers() {
              return 0;
            }
          };
      assertThatThrownBy(noneAllowed::onePostgresContainerPerJvm)
          .isInstanceOf(AssertionFailedError.class)
          .hasMessageStartingWith(
              "1 Platform PostgreSQL containers run in this JVM, at most 0 expected: import"
                  + " PlatformSharedPostgresContainer instead of a container bean per context");
    }
  }

  private static ConfigurableApplicationContext start(Class<?> application) {
    return new SpringApplicationBuilder(application)
        .web(WebApplicationType.NONE)
        .properties("spring.main.banner-mode=off")
        .run();
  }

  private static JdbcTemplate jdbc(ConfigurableApplicationContext context) {
    return context.getBean(JdbcTemplate.class);
  }

  private static long systemIdentifier(ConfigurableApplicationContext context) {
    Long identifier =
        jdbc(context)
            .queryForObject("SELECT system_identifier FROM pg_control_system()", Long.class);
    assertThat(identifier).isNotNull();
    return identifier;
  }

  @SpringBootConfiguration(proxyBeanMethods = false)
  // Tylko JDBC: JPA, Modulith, Liquibase i Flyway z classpath testów nie zakładają nic we wspólnej
  // bazie.
  @ImportAutoConfiguration({
    TestcontainersPropertySourceAutoConfiguration.class,
    DataSourceAutoConfiguration.class,
    JdbcTemplateAutoConfiguration.class
  })
  @Import(PlatformSharedPostgresContainer.class)
  static class FirstApplication {}

  @SpringBootConfiguration(proxyBeanMethods = false)
  // Tylko JDBC: JPA, Modulith, Liquibase i Flyway z classpath testów nie zakładają nic we wspólnej
  // bazie.
  @ImportAutoConfiguration({
    TestcontainersPropertySourceAutoConfiguration.class,
    DataSourceAutoConfiguration.class,
    JdbcTemplateAutoConfiguration.class
  })
  @Import(PlatformSharedPostgresContainer.class)
  static class SecondApplication {

    @Bean
    String secondContextMarker() {
      return "a different context signature";
    }
  }
}
