# roadmap toolkit — kanoniczna logika (Platform) + per-repo config

Ujednolicony toolkit „roadmap → GitHub Issues + Projects v2 + auto-unblock". **Logika jest
kanoniczna w Platform** (jedno źródło prawdy); repo konsumenckie trzyma **jeden** plik wartości:
`scripts/lib/roadmap-config.sh`. Wszystkie repo mają identyczny format `roadmap.md`, więc parser jest wspólny.

## Pliki (kanon → cel u konsumenta)

| Plik kanoniczny (`templates/roadmap/`) | Cel u konsumenta | Rola |
|---|---|---|
| `scripts/roadmap-to-issues.sh` | `scripts/roadmap-to-issues.sh` | idempotentna projekcja roadmapy → Issues + Projects v2 (klucz: marker `roadmap-id:`) |
| `scripts/roadmap-unblock.sh` | `scripts/roadmap-unblock.sh` | auto-unblock zależnych po zamknięciu prerekwizytu; **kontrakt `--closed <N>`** (woła go reusable) |
| `scripts/roadmap-project-setup.sh` | `scripts/roadmap-project-setup.sh` | jednorazowy bootstrap pól board (Status/Stream/Roadmap ID) |
| `scripts/lib/roadmap-parse.sh` | `scripts/lib/roadmap-parse.sh` | parser `roadmap.md` → TSV + helpery markera (kanon) |
| `scripts/lib/roadmap-lib.sh` | `scripts/lib/roadmap-lib.sh` | helpery label/status nad wartościami z configu (kanon) |
| `scripts/lib/roadmap-config.sh.example` | `scripts/lib/roadmap-config.sh` | **jedyny per-repo** — wartości (tytuł, ścieżki, palety kolorów); NIE re-syncowany |
| `scripts/lib/roadmap-parse.test.sh`, `roadmap-libs.test.sh` | `scripts/lib/…` | testy (fixture + statyczny sanity) |
| `scripts/lib/fixtures/roadmap.sample.md` | `scripts/lib/fixtures/…` | fixture do hermetycznego testu parsera |
| `examples/roadmap-config.{bookofstyling,skillsprintplus}.sh` | — | gotowe wartości per-repo (referencja rolloutu) |

Kolejność source w każdym skrypcie: `roadmap-config.sh` → `roadmap-lib.sh` → `roadmap-parse.sh`.

## Rollout do repo (BoS/SSP i kolejne)

1. Skopiuj `templates/roadmap/scripts/**` do `scripts/**` repo (nadpisuje stare, rozjechane skrypty).
2. Utwórz `scripts/lib/roadmap-config.sh` z `roadmap-config.sh.example` (BoS/SSP: użyj gotowca z `examples/`).
3. Zostaw cienki caller `.github/workflows/roadmap-unblock.yml` (`uses: …/Platform/…@v1` + `secrets: inherit`) — kontrakt `--closed` się nie zmienia.
4. **Self-heal markera** (bezpieczny): odpal `./scripts/roadmap-to-issues.sh --dry-run` (podgląd), potem bez `--dry-run`.
   Lookup po stabilnym `roadmap-id:` znajduje istniejące Issue → **update**, nie duplikat; przy okazji przepisuje marker do kanonicznego układu. Wymaga PAT `ROADMAP_PROJECT_TOKEN` (scope `project`).

## Uwaga
- Idempotencja stoi na markerze `roadmap-id:` — nie zmieniaj jego formatu bez migracji.
- Skrypty mutują GitHub (Issues/Projects v2). Zawsze najpierw `--dry-run`.
- `GH_REPO`/`GH_OWNER` = env lub autodetekcja; `ROADMAP_PROJECT_NUMBER` = repo `var`/`--project` (świadomie poza configiem).
