package example.app;

import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;

@Tag("integration")
@SpringBootTest
class ApplicationTest {
  @Test
  void startsWithPlatformConventions() {}
}
