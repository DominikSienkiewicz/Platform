# infra — szablon środowiska dev

Współdzielony `docker-compose` dla repo konsumenckich. **PostgreSQL + pgvector** zawsze;
**Ollama** opcjonalnie (profil `ai`, dla repo local-first jak Attestate).

```bash
cp .env.example .env            # dostosuj POSTGRES_DB/USER/PASSWORD
docker compose up -d            # samo Postgres+pgvector
docker compose --profile ai up -d   # + Ollama
```

| Usługa | Obraz | Port (default) |
|---|---|---|
| postgres | `pgvector/pgvector` | 5432 |
| ollama (profil `ai`) | `ollama/ollama` | 11434 |

`postgres/init/01-extensions.sql` tworzy rozszerzenie `vector` przy pierwszej inicjalizacji wolumenu.

Wolumen `postgres-data` jest montowany w `/var/lib/postgresql`, nie w `/var/lib/postgresql/data`:
od PostgreSQL 18 oficjalny obraz ustawia `PGDATA=/var/lib/postgresql/18/docker`, więc przy starym
punkcie montowania pg18 odmawia startu, a dane spoza wolumenu nie przetrwałyby `docker compose down`.

> Jak używać: skopiuj `infra/` do repo konsumenta (lub trzymaj jako submodule) i nadpisz `.env`.
> Źródłem tagów obrazów jest `PlatformImages.java` w `gradle/test-fixtures` (obrazy Testcontainers);
> `docker-compose.yml` jest jego lustrem, a rozjazd wywala `templates/tests/image-tags-sync.test.sh`.
> Renovate bumpuje oba pliki w jednej gałęzi. Tagi celowo nie stoją w tabeli wyżej — trzecia kopia
> nie miałaby managera.
