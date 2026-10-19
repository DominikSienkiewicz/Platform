package example.app.accounts;

import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Service;

/** Otwiera konta i ogłasza każde zdarzeniem {@link AccountOpened}. */
@Service
public class Accounts {
  private final ApplicationEventPublisher events;

  public Accounts(ApplicationEventPublisher events) {
    this.events = events;
  }

  public void open(String accountId) {
    events.publishEvent(new AccountOpened(accountId));
  }
}
