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
| postgres | `pgvector/pgvector:0.8.2-pg18` | 5432 |
| ollama (profil `ai`) | `ollama/ollama:0.30.6` | 11434 |

`postgres/init/01-extensions.sql` tworzy rozszerzenie `vector` przy pierwszej inicjalizacji wolumenu.

> Jak używać: skopiuj `infra/` do repo konsumenta (lub trzymaj jako submodule) i nadpisz `.env`.
> Wersje obrazów są jednym źródłem prawdy — bump tutaj, nie w każdym repo z osobna.
