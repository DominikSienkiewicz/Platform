# infra — development environment template

A shared `docker-compose` for the consumer repositories. **PostgreSQL with pgvector** always;
**Ollama** optionally (profile `ai`, for local-first repositories such as Attestate).

```bash
cp .env.example .env                 # adjust POSTGRES_DB/USER/PASSWORD
docker compose up -d                 # PostgreSQL with pgvector only
docker compose --profile ai up -d    # plus Ollama
```

| Service | Image | Port (default) |
|---|---|---|
| postgres | `pgvector/pgvector` | 5432 |
| ollama (profile `ai`) | `ollama/ollama` | 11434 |

`postgres/init/01-extensions.sql` creates the `vector` extension when the volume is first initialised.

The `postgres-data` volume is mounted at `/var/lib/postgresql`, not at `/var/lib/postgresql/data`:
from PostgreSQL 18 on, the official image sets `PGDATA=/var/lib/postgresql/18/docker`, so with the old
mount point pg18 refuses to start, and data outside the volume would not survive `docker compose down`.

> How to use it: copy `infra/` into the consumer repository (or keep it as a submodule) and override
> `.env`. The image tags come from `PlatformImages.java` in `gradle/test-fixtures` (the Testcontainers
> images); `docker-compose.yml` mirrors it, and `templates/tests/image-tags-sync.test.sh` fails when they
> drift. Renovate (the Platform preset) bumps both files in one branch once the Renovate app runs in the
> repository. The tags are deliberately not in the table above: a third copy would have no manager.
