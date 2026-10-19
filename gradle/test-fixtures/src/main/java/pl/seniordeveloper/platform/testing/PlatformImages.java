package pl.seniordeveloper.platform.testing;

/**
 * Jedno źródło prawdy tagów obrazów kontenerów testowych — likwiduje rozjazd, który był między repo
 * (np. {@code :pg18} vs {@code :0.8.2-pg18}).
 *
 * <p>Lustro: {@code infra/docker-compose.yml} (lokalne środowisko dev); równość tagów pilnuje
 * {@code templates/tests/image-tags-sync.test.sh}. Preset Renovate ({@code Platform/default.json},
 * customManager docker) proponuje bump tych stałych, a compose swoim managerem w tej samej gałęzi —
 * o ile aplikacja Renovate działa w repo; do tego czasu tagi podbija się ręcznie.
 */
public final class PlatformImages {

  /** PostgreSQL 18 + pgvector (RAG / embeddings). */
  public static final String PGVECTOR = "pgvector/pgvector:0.8.2-pg18";

  /** Ollama (local-first AI — np. Attestate). */
  public static final String OLLAMA = "ollama/ollama:0.32.3";

  private PlatformImages() {}
}
