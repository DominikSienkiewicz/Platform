package example.library;

import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Test;

class GreetingTest {
  @Test
  void formatsGreeting() {
    assertEquals("Hello, Platform", new Greeting("Platform").message());
  }
}
