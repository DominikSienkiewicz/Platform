#!/usr/bin/env bash
# Exercise the 1.x smoke init script without resolving any plugin or downloading Maven artifacts.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
project=$(mktemp -d)
trap 'rm -rf "$project"' EXIT
cat > "$project/settings.gradle" <<'GRADLE'
rootProject.name = 'legacy-repository-test'
def repos = dependencyResolutionManagement.repositories
repos.maven {
    name = 'platform'
    url = uri('https://maven.pkg.github.com/DominikSienkiewicz/Platform')
    credentials { username = 'fixture'; password = 'fixture' }
}
repos.maven { name = 'other'; url = uri('https://example.invalid/unchanged') }
gradle.rootProject { project ->
    project.tasks.register('checkMirror') {
        doLast {
            assert repos.platform.url.toString() == 'https://maven.pkg.github.com/seniordeveloper-pl-dominik-sienkiewicz/Platform'
            assert repos.platform.credentials.username == 'fixture'
            assert repos.platform.credentials.password == 'fixture'
            assert repos.other.url.toString() == 'https://example.invalid/unchanged'
        }
    }
}
GRADLE
"${PLATFORM_TEST_GRADLE:-$root/gradle/build-logic/gradlew}" --offline --max-workers=1 --no-parallel --no-daemon \
  --project-dir "$project" --init-script "$root/gradle/legacy-smoke-repository.init.gradle" checkMirror
