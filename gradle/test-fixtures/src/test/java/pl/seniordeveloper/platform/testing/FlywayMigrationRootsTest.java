package pl.seniordeveloper.platform.testing;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.net.URL;
import java.net.URLClassLoader;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.jar.JarEntry;
import java.util.jar.JarOutputStream;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

/** Każdy root {@code db/migration} na classpath, z katalogu i z jara, rekurencyjnie. */
class FlywayMigrationRootsTest {

  @TempDir Path directory;

  @Test
  void rootsFromADirectoryAndAJarAreWalkedRecursively() throws Exception {
    var classes = directory.resolve("classes");
    Files.createDirectories(classes.resolve("db/migration/sub"));
    Files.writeString(classes.resolve("db/migration/V1__a.sql"), "select 1;");
    Files.writeString(classes.resolve("db/migration/sub/V2__b.sql"), "select 2;");
    var jar = directory.resolve("migrations.jar");
    writeJar(jar, "db/migration/V3__c.sql", "db/migration/README.md");

    try (var loader =
        new URLClassLoader(new URL[] {classes.toUri().toURL(), jar.toUri().toURL()}, null)) {
      var roots = AbstractFlywayMigrationTest.migrationRoots(loader);

      assertThat(roots).hasSize(2);
      assertThat(roots.values()).containsExactly(java.util.List.of("V1__a.sql", "sub/V2__b.sql"), java.util.List.of("V3__c.sql"));
    }
  }

  private static void writeJar(Path jar, String... entries) throws IOException {
    try (var out = new JarOutputStream(Files.newOutputStream(jar))) {
      out.putNextEntry(new JarEntry("db/"));
      out.closeEntry();
      out.putNextEntry(new JarEntry("db/migration/"));
      out.closeEntry();
      for (var entry : entries) {
        out.putNextEntry(new JarEntry(entry));
        out.write("select 3;".getBytes(StandardCharsets.UTF_8));
        out.closeEntry();
      }
    }
  }
}
