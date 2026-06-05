-- Rozszerzenia PostgreSQL. Uruchamiane jednorazowo przy inicjalizacji świeżego wolumenu danych.
CREATE EXTENSION IF NOT EXISTS vector;  -- pgvector (RAG / embeddings)
-- UUIDv7: generuj po stronie aplikacji lub natywnie (PG 18: uuidv7()). uuid-ossp niepotrzebne.
