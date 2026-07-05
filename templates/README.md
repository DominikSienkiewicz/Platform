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
| `platform-bump.sh` | **stub** delegujący do binu `platform-bump` z `@dominiksienkiewicz/versions` (`frontend/node_modules/.bin`); logika bumpu żyje w pakiecie npm, nie tutaj — drift-proof. Wymaga pinu `@dominiksienkiewicz/versions` ≥ 1.3.8 | root każdego repo |
| `merge.sh` | integracja gałęzi feature z worktree do `main` + sprzątanie (usuwa worktree, kasuje gałąź); odmawia na brudnym drzewie i gałęziach chronionych | root każdego repo |

Testy skryptów szablonowych żyją w `tests/` (odpalane w CI, job „Templates").

CI (reusable workflows), wersje (catalog), jakość (convention plugins), config lintera, paczki FE
i Renovate-preset są dystrybuowane automatycznie (artefakty/`extends`) — nie ma ich tutaj.
