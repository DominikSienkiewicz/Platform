package pl.seniordeveloper.platform.testing;

/**
 * Jedno źródło prawdy tagów obrazów kontenerów testowych — likwiduje rozjazd, który był między repo
 * (np. {@code :pg18} vs {@code :0.8.2-pg18}).
 *
 * <p>Preset Renovate ({@code Platform/default.json}, customManager docker) proponuje bump tych
 * stałych — o ile aplikacja Renovate działa w repo; do tego czasu tagi podbija się ręcznie.
 */
public final class PlatformImages {

  /** PostgreSQL 18 + pgvector (RAG / embeddings). */
  public static final String PGVECTOR = "pgvector/pgvector:0.8.7-pg18";

  private PlatformImages() {}
}
