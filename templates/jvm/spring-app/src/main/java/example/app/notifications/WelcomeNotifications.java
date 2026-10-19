package example.app.notifications;

import example.app.accounts.AccountOpened;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

/** Wita nowe konto; moduł accounts zna tylko przez jego zdarzenie, nie przez wywołanie. */
@Component
class WelcomeNotifications {
  private static final Logger LOG = LoggerFactory.getLogger(WelcomeNotifications.class);

  @EventListener
  void on(AccountOpened event) {
    LOG.info("Welcome, account {}", event.accountId());
  }
}
