package pl.seniordeveloper.platform.testing.arch.fixture.clean;

import org.springframework.context.annotation.Import;
import pl.seniordeveloper.platform.testing.IntegrationTest;
import pl.seniordeveloper.platform.testing.PlatformPostgresContainer;

@IntegrationTest
@Import(PlatformPostgresContainer.class)
public class TaggedContainerTest {}
