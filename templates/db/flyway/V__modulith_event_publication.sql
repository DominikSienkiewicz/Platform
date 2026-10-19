-- CANON (Platform/templates/db/flyway/V__modulith_event_publication.sql).
-- Tabela rejestru publikacji zdarzeń Spring Modulith dla spring-modulith-starter-jpa (tryb UPDATE i DELETE).
-- spring-modulith-events-jpa nie dostarcza SQL-a, a bez tabeli rejestr po cichu nie zapisuje publikacji.
-- Schemat odpowiada encji JpaEventPublication wersji Modulith z katalogu Platform; AbstractSchemaValidationIT
-- w test-fixtures waliduje go Hibernate'em na PostgreSQL. Kopiuj jako db/migration/V<n>__modulith_event_publication.sql
-- (następna wolna wersja). IF NOT EXISTS: repo, które założyło tabelę ręcznie, przyjmuje migrację bez błędu.
CREATE TABLE IF NOT EXISTS event_publication
(
  id                     UUID                     NOT NULL,
  listener_id            TEXT                     NOT NULL,
  event_type             TEXT                     NOT NULL,
  serialized_event       TEXT                     NOT NULL,
  publication_date       TIMESTAMP WITH TIME ZONE NOT NULL,
  completion_date        TIMESTAMP WITH TIME ZONE,
  status                 TEXT,
  completion_attempts    INTEGER                  NOT NULL DEFAULT 0,
  last_resubmission_date TIMESTAMP WITH TIME ZONE,
  PRIMARY KEY (id)
);
CREATE INDEX IF NOT EXISTS event_publication_serialized_event_hash_idx ON event_publication USING hash (serialized_event);
CREATE INDEX IF NOT EXISTS event_publication_by_completion_date_idx ON event_publication (completion_date);
