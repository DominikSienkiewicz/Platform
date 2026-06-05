package pl.seniordeveloper.platform.testing;

/**
 * Jedno źródło prawdy tagów obrazów kontenerów testowych — likwiduje rozjazd, który był między
 * repo (np. {@code pgvector/pgvector:pg18} vs {@code :0.8.2-pg18}).
 *
 * <p>Lustro {@code gradle/catalog} ({@code pgvectorImage} / {@code ollamaImage}); Renovate bumpuje
 * te stałe przez customManager (datasource: docker) — patrz {@code Platform/default.json}.
 */
public final class PlatformImages {

  /** PostgreSQL 18 + pgvector (RAG / embeddings). */
  public static final String PGVECTOR = "pgvector/pgvector:0.8.2-pg18";

  /** Ollama (local-first AI — np. Attestate). */
  public static final String OLLAMA = "ollama/ollama:0.30.6";

  private PlatformImages() {}
}
