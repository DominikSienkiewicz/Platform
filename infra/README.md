# infra — development environment template

A shared `docker-compose` for the consumer repositories. **PostgreSQL with pgvector** always;
**Ollama** optionally (profile `ai`, for local-first repositories such as Attestate); the metrics and traces of
an application running on the host optionally (profile `observability`).

```bash
cp .env.example .env                 # adjust POSTGRES_DB/USER/PASSWORD
docker compose up -d                 # PostgreSQL with pgvector only
docker compose --profile ai up -d    # plus Ollama
docker compose --profile observability up -d   # plus otel-collector, Tempo, Prometheus and Grafana
```

| Service | Image | Port (default) |
|---|---|---|
| postgres | `pgvector/pgvector` | 5432 |
| ollama (profile `ai`) | `ollama/ollama` | 11434 |
| otel-collector (profile `observability`) | `otel/opentelemetry-collector` | 4318 (OTLP HTTP) |
| tempo (profile `observability`) | `grafana/tempo` | none, Grafana reads it |
| prometheus (profile `observability`) | `prom/prometheus` | 9090 |
| grafana (profile `observability`) | `grafana/grafana` | 3001 |

The `observability` profile is the stack of `Azimuth/observability/`, for an application that runs on the host
with the observability starter: Prometheus scrapes `host.docker.internal:8080/actuator/prometheus`
(`platform.observability.prometheus=true`; edit `observability/prometheus.yaml` for another port), the
`tracing` variant exports to `http://localhost:4318` (`management.opentelemetry.tracing.export.otlp.endpoint`),
and Grafana opens without a login, with Prometheus and Tempo provisioned as data sources. It is for local use
only: Grafana's anonymous user is an administrator.

`postgres/init/01-extensions.sql` creates the `vector` extension when the volume is first initialised.

The `postgres-data` volume is mounted at `/var/lib/postgresql`, not at `/var/lib/postgresql/data`:
from PostgreSQL 18 on, the official image sets `PGDATA=/var/lib/postgresql/18/docker`, so with the old
mount point pg18 refuses to start, and data outside the volume would not survive `docker compose down`.

> How to use it: copy `infra/` into the consumer repository (or keep it as a submodule) and override
> `.env`. The image tags come from `PlatformImages.java` in `gradle/test-fixtures` (the Testcontainers
> images); `docker-compose.yml` mirrors it, and `templates/tests/image-tags-sync.test.sh` fails when they
> drift. Renovate (the Platform preset) bumps both files in one branch once the Renovate app runs in the
> repository. The tags are deliberately not in the table above: a third copy would have no manager.
