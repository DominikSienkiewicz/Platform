package pl.seniordeveloper.gradle.fixture;

import java.io.IOException;
import java.util.List;

class FormatterCorpus {
  @Deprecated private final int legacy = 1;
  @SuppressWarnings("unused") private final List<String> names = List.of();
  private final Runnable noop = () -> {};
  private final Object anonymous = new Object() {};

  record Point() {}

  interface Shape {}

  interface Named {}

  <T extends Shape & Named> T pick(T value) { return value; }

  String text() {
    return """
        multi
        line
        """;
  }

  int expression(int x) {
    var label = switch (x) { case 1 -> 10; case 2 -> { int doubled = x * 2; yield doubled; } default -> 0; };
    return label;
  }

  void statement(int x) {
    switch (x) { case 1 -> {} default -> {} }
  }

  void ignore() {
    try { risky(); } catch (IOException ignored) {}
  }

  void risky() throws IOException {}
}
