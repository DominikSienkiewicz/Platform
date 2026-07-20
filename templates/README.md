# templates — kanoniczne pliki współdzielone (source of truth)

Pliki, których **nie da się** dystrybuować przez registry (są per-repo z natury), ale mają jedno
źródło prawdy tutaj. Przy zmianie: edytuj tu, potem zsynchronizuj do repo konsumenckich.

| Plik | Cel | Gdzie kopiować |
|---|---|---|
| `.editorconfig` | spójny styl IDE/OS | root każdego repo |
| `gitignore/root.gitignore` | OS/IDE/env/logs | `<repo>/.gitignore` |
| `gitignore/backend.gitignore` | Java/Gradle | `<repo>/backend/.gitignore` |
| `gitignore/frontend.gitignore` | Next.js/Node/Playwright | `<repo>/frontend/.gitignore` |
| `Dockerfile.backend` | runtime-only (jar z `bootJar`) | `<repo>/backend/Dockerfile` |
| `platform-bump.sh` | **stub** delegujący do binu `platform-bump` z `@dominiksienkiewicz/versions` (`frontend/node_modules/.bin`); logika bumpu żyje w pakiecie npm, nie tutaj — drift-proof. Wymaga pinu `@dominiksienkiewicz/versions` ≥ 1.3.8 | `<repo>/scripts/platform-bump.sh` |
| `merge.sh` | integracja gałęzi feature z worktree do `main` + sprzątanie (usuwa worktree, kasuje gałąź); odmawia na brudnym drzewie i gałęziach chronionych | `<repo>/scripts/merge.sh` |
| `setup-gh-deploy.sh` | bootstrap sekretów+zmiennych Actions dla reusable `deploy.yml@v1` z lokalnego `.secrets.local` (bezpieczny parser, wartości przez stdin, `SSH_KNOWN_HOSTS` z ssh-keyscan; opcje `--gen-key`, `--with-release`) | `<repo>/scripts/setup-gh-deploy.sh` |
| `secrets.local.example` | szablon lokalnego pliku wartości dla `setup-gh-deploy.sh` (nazwy sekretów/zmiennych = kontrakt reusable deploy) | `<repo>/.secrets.local.example` |
| `roadmap/` | **toolkit roadmap→Issues+Projects v2** (poddrzewo): kanoniczna logika (`roadmap-{to-issues,unblock,project-setup}.sh` + `lib/`) + per-repo `roadmap-config.sh`. Szczegóły i rollout w [`roadmap/README.md`](roadmap/README.md) | `<repo>/scripts/**` (config: `scripts/lib/roadmap-config.sh`) |

Testy skryptów szablonowych żyją w `tests/` (odpalane w CI, job „Templates").

CI (reusable workflows), wersje (catalog), jakość (convention plugins), config lintera, paczki FE
i Renovate-preset są dystrybuowane automatycznie (artefakty/`extends`) — nie ma ich tutaj.
