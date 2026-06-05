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

CI (reusable workflows), wersje (catalog), jakość (convention plugins), config lintera, paczki FE
i Renovate-preset są dystrybuowane automatycznie (artefakty/`extends`) — nie ma ich tutaj.
