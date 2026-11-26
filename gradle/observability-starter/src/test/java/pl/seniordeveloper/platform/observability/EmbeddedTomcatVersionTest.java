package pl.seniordeveloper.platform.observability;

import static org.assertj.core.api.Assertions.assertThat;

import java.lang.module.ModuleDescriptor.Version;
import org.apache.catalina.startup.Tomcat;
import org.apache.el.ExpressionFactoryImpl;
import org.apache.tomcat.websocket.WsWebSocketContainer;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

class EmbeddedTomcatVersionTest {
  @ParameterizedTest
  @ValueSource(classes = {Tomcat.class, ExpressionFactoryImpl.class, WsWebSocketContainer.class})
  void webMvcResolvesPatchedTomcatArtifacts(Class<?> component) {
    var version = Version.parse(component.getPackage().getImplementationVersion());
    assertThat(version).as(component.getName()).isGreaterThanOrEqualTo(Version.parse("11.0.29"));
  }
}
