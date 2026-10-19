package pl.seniordeveloper.platform.testing.arch.fixture.violating;

import org.springframework.context.annotation.Import;
import pl.seniordeveloper.platform.testing.PlatformPostgresContainer;

@Import(PlatformPostgresContainer.class)
public class UntaggedContainerTest {}
