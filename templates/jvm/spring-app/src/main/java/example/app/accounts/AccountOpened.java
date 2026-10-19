package example.app.accounts;

/**
 * Zdarzenie modułu accounts: {@link Accounts} publikuje je po otwarciu konta, a inne moduły na nie
 * nasłuchują.
 */
public record AccountOpened(String accountId) {}
