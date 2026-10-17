# templates — kanoniczne pliki współdzielone (source of truth)

Pliki, których **nie da się** dystrybuować przez registry (są per-repo z natury), ale mają jedno
źródło prawdy tutaj. Przy zmianie: edytuj tu, potem zsynchronizuj do repo konsumenckich.

| Plik | Cel | Gdzie kopiować |
|---|---|---|
| `jvm/java-library/`, `jvm/spring-app/` | minimalne projekty konsumujące opublikowane pluginy i katalog; sprawdzane przez Gradle TestKit. Ich `.gitignore` = reguły `gitignore/root.gitignore` + `gitignore/backend.gitignore` | root nowego repo; instrukcja w [consuming.md](../docs/consuming.md) |
| `agent-gradle.sh` | opt-in limity workerów przy `AI_AGENT=1/true`; uruchamia `./gradlew` z roota, a gdy go nie ma — `backend/gradlew` z `backend/` | `<repo>/scripts/agent-gradle.sh` |
| `.editorconfig` | spójny styl IDE/OS (Java: 2 spacje jak google-java-format; Kotlin/`*.kts`: taby) | root każdego repo |
| `.sdkmanrc` | lokalny JDK do uruchamiania Gradle przez SDKMAN (`sdk env`) | root każdego repo |
| `gitignore/root.gitignore` | OS/IDE/env/`.secrets.local`/logs | `<repo>/.gitignore` |
| `gitignore/backend.gitignore` | Java/Gradle, wyjście IntelliJ (`out/`) i Buildship (`bin/`) | `<repo>/backend/.gitignore` |
| `gitignore/frontend.gitignore` | Next.js/Node/Playwright | `<repo>/frontend/.gitignore` |
| `Dockerfile.backend` | runtime-only (jar z `bootJar`) na `sapmachine:27-jre` — powód i warunek powrotu na Temurin w [`../docs/versions.md`](../docs/versions.md) | `<repo>/backend/Dockerfile` |
| `platform-bump.sh` | **stub** delegujący do binu `platform-bump` z `@dominiksienkiewicz/versions` (`frontend/node_modules/.bin`); logika bumpu żyje w pakiecie npm, nie tutaj — drift-proof. Wymaga pinu `@dominiksienkiewicz/versions` ≥ 1.3.8 | `<repo>/scripts/platform-bump.sh` |
| `bump-version.sh` | bump wersji warstwy aplikacji (`backend`/`frontend`) i nowy changeset Liquibase (`db new-migration`); to nie jest `platform-bump.sh` | `<repo>/scripts/bump-version.sh` |
| `merge.sh` | bezpieczna integracja lokalnej gałęzi feature z wymaganym komunikatem merge; preflight worktree (także plików ignored) i lokalnego targetu, kontrola świeżości `origin/<target>`, blokada równoległych uruchomień, `--dry-run`, jawny tryb `--offline`, atomowy cleanup oraz jednoznaczny wynik: zielone `✓` przy sukcesie, czerwone `✗` przy każdej porażce (`NO_COLOR` wyłącza kolor, `FORCE_COLOR` wymusza go poza terminalem) | `<repo>/scripts/merge.sh` |
| `setup-gh-deploy.sh` | bootstrap sekretów+zmiennych Actions dla reusable `deploy.yml@v1` z lokalnego `.secrets.local` (bezpieczny parser, wartości przez stdin, `SSH_KNOWN_HOSTS` z ssh-keyscan; opcje `--gen-key`, `--with-release`); odmawia pracy, gdy git nie ignoruje `.secrets.local` | `<repo>/scripts/setup-gh-deploy.sh` |
| `secrets.local.example` | szablon lokalnego pliku wartości dla `setup-gh-deploy.sh` (nazwy sekretów/zmiennych = kontrakt reusable deploy) | `<repo>/.secrets.local.example` |
| `roadmap/` | **toolkit roadmap→Issues+Projects v2** (poddrzewo): kanoniczna logika (`roadmap-{to-issues,unblock,project-setup}.sh` + `lib/`) + per-repo `roadmap-config.sh`. Szczegóły i rollout w [`roadmap/README.md`](roadmap/README.md) | `<repo>/scripts/**` (config: `scripts/lib/roadmap-config.sh`) |
| `github/CODEOWNERS` | domyślny właściciel całego repo | `<repo>/.github/CODEOWNERS` |
| `github/pull_request_template.md` | szablon opisu PR (cel zmiany + checklista) | `<repo>/.github/pull_request_template.md` |

Testy skryptów szablonowych żyją w `templates/tests/` (odpalane w CI, job „Templates”). Platform
używa kanonicznego `templates/merge.sh` przez cienki delegat [`../merge.sh`](../merge.sh), dzięki
czemu własna kopia helpera nie może się rozjechać z kanonem.

CI (reusable workflows), wersje (catalog), jakość (convention plugins), config lintera, paczki FE
i Renovate-preset są dystrybuowane automatycznie (artefakty/`extends`) — nie ma ich tutaj.

Project concepts, feature proposals, plans, and audits belong in local
`docs/concepts/`. The root Git ignore templates exclude that directory;
maintained technical documentation elsewhere under `docs/` stays versioned.
