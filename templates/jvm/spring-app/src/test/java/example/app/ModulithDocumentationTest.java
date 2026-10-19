package example.app;

import pl.seniordeveloper.platform.testing.AbstractModulithDocumentationTest;

class ModulithDocumentationTest extends AbstractModulithDocumentationTest {
  @Override
  protected Class<?> applicationClass() {
    return Application.class;
  }
}
