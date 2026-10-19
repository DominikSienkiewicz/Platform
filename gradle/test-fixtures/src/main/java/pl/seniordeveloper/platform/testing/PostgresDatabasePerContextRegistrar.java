package pl.seniordeveloper.platform.testing;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.concurrent.atomic.AtomicInteger;
import org.jspecify.annotations.Nullable;
import org.springframework.beans.factory.DisposableBean;
import org.springframework.beans.factory.SmartInitializingSingleton;
import org.springframework.core.env.Environment;
import org.springframework.test.context.DynamicPropertyRegistrar;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.testcontainers.postgresql.PostgreSQLContainer;

/**
 * Baza jednego kontekstu z {@link PlatformPostgresDatabasePerContext}: przy starcie kontekstu
 * zakłada {@code ctx_<n>} na wspólnym serwerze i kieruje na nią {@code spring.datasource.*}, po
 * utworzeniu singletonów sprawdza, że nikt tego adresu nie nadpisał, a przy zamknięciu kontekstu
 * kasuje bazę.
 */
final class PostgresDatabasePerContextRegistrar
    implements DynamicPropertyRegistrar, SmartInitializingSingleton, DisposableBean {

  static final String URL_PROPERTY = "spring.datasource.url";

  private static final String JDBC_PREFIX = "jdbc:postgresql://";

  private static final String DATABASE_PREFIX = "ctx_";

  // SQLSTATE duplicate_database: nazwę zajęła inna JVM na kontenerze z reuse albo baza z
  // poprzedniego uruchomienia, której nikt nie skasował.
  private static final String DUPLICATE_DATABASE = "42P04";

  private static final AtomicInteger LAST_DATABASE = new AtomicInteger();

  private final Environment environment;

  private volatile @Nullable String database;

  private volatile @Nullable String url;

  PostgresDatabasePerContextRegistrar(Environment environment) {
    this.environment = environment;
  }

  @Override
  public void accept(DynamicPropertyRegistry registry) {
    PostgreSQLContainer server = PlatformSharedPostgresContainer.container();
    String created = createDatabase(server);
    String createdUrl = jdbcUrl(server.getJdbcUrl(), created);
    database = created;
    url = createdUrl;
    registry.add(URL_PROPERTY, () -> createdUrl);
    registry.add("spring.datasource.username", server::getUsername);
    registry.add("spring.datasource.password", server::getPassword);
  }

  @Override
  public void afterSingletonsInstantiated() {
    String own = url;
    if (own != null) {
      requireOwnDatabase(own, environment.getProperty(URL_PROPERTY));
    }
  }

  @Override
  public void destroy() throws SQLException {
    String created = database;
    if (created == null) {
      return;
    }
    // FORCE zamyka połączenia, które przeżyły pulę kontekstu.
    try (Connection connection = connect(PlatformSharedPostgresContainer.container());
        Statement statement = connection.createStatement()) {
      statement.execute("DROP DATABASE IF EXISTS " + created + " WITH (FORCE)");
    }
  }

  /**
   * Adres bazy na tym samym serwerze, z parametrami adresu serwera.
   *
   * @param serverUrl adres JDBC wspólnego kontenera, np. {@code
   *     jdbc:postgresql://localhost:55432/test?loggerLevel=OFF}
   * @param database nazwa bazy kontekstu
   * @return {@code serverUrl} z {@code database} w miejscu bazy
   */
  static String jdbcUrl(String serverUrl, String database) {
    int path = serverUrl.indexOf('/', JDBC_PREFIX.length());
    int query = serverUrl.indexOf('?', path);
    String parameters = query < 0 ? "" : serverUrl.substring(query);
    return serverUrl.substring(0, path + 1) + database + parameters;
  }

  /**
   * Failuje kontekst, w którym późniejsza rejestracja zastąpiła adres bazy kontekstu: wtedy
   * konteksty po cichu dzieliłyby wspólną bazę.
   *
   * @param ownUrl adres bazy kontekstu
   * @param registeredUrl {@code spring.datasource.url}, który kontekst faktycznie widzi
   * @throws IllegalStateException gdy adresy się różnią
   */
  static void requireOwnDatabase(String ownUrl, @Nullable String registeredUrl) {
    if (!ownUrl.equals(registeredUrl)) {
      throw new IllegalStateException(
          "spring.datasource.url of this context is "
              + registeredUrl
              + " instead of its own database "
              + ownUrl
              + ": something registered it after @PlatformPostgresDatabasePerContext. Import"
              + " PlatformSharedPostgresContainer through @PostgresIntegrationTest or @Import, not as"
              + " an application source");
    }
  }

  private static String createDatabase(PostgreSQLContainer server) {
    try (Connection connection = connect(server);
        Statement statement = connection.createStatement()) {
      String candidate;
      do {
        candidate = DATABASE_PREFIX + LAST_DATABASE.incrementAndGet();
      } while (!create(statement, candidate));
      return candidate;
    } catch (SQLException exception) {
      throw new IllegalStateException(
          "Cannot create a database for this context on the shared PostgreSQL", exception);
    }
  }

  // false, gdy nazwa jest zajęta: następna próba bierze kolejny numer.
  private static boolean create(Statement statement, String candidate) throws SQLException {
    try {
      statement.execute("CREATE DATABASE " + candidate);
      return true;
    } catch (SQLException exception) {
      if (DUPLICATE_DATABASE.equals(exception.getSQLState())) {
        return false;
      }
      throw exception;
    }
  }

  // DriverManager, nie createConnection() kontenera: tamto ponawia próby do 120 s, a DROP przy
  // końcu JVM nie może czekać na kontener, którego już nie ma.
  private static Connection connect(PostgreSQLContainer server) throws SQLException {
    return DriverManager.getConnection(
        server.getJdbcUrl(), server.getUsername(), server.getPassword());
  }
}
