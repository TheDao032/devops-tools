-- Claude memory database schema.
-- Markdown vault is source of truth; everything here is rebuildable from disk.

CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_trgm;   -- for fuzzy text matching on titles/tags

-- =====================================================================
-- Documents — one row per markdown file in the vault
-- =====================================================================
CREATE TABLE IF NOT EXISTS vault_documents (
    id              BIGSERIAL PRIMARY KEY,
    path            TEXT UNIQUE NOT NULL,            -- relative to vault root, e.g. "40-decisions/2026-04-30-foo.md"
    note_id         TEXT NOT NULL,                   -- frontmatter `id`, must match filename stem
    title           TEXT NOT NULL,
    type            TEXT NOT NULL CHECK (type IN ('project','area','reference','decision','conversation','daily','meta','moc')),
    status          TEXT NOT NULL CHECK (status IN ('active','draft','archived','superseded')),
    created_at      DATE NOT NULL,                   -- frontmatter `created`
    updated_at      DATE NOT NULL,                   -- frontmatter `updated`
    content_hash    TEXT NOT NULL,                   -- sha256 of body, for dedup + change detection
    frontmatter     JSONB NOT NULL DEFAULT '{}'::jsonb,
    body_chars      INTEGER NOT NULL DEFAULT 0,
    indexed_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS vault_documents_type_idx       ON vault_documents (type);
CREATE INDEX IF NOT EXISTS vault_documents_status_idx     ON vault_documents (status);
CREATE INDEX IF NOT EXISTS vault_documents_updated_idx    ON vault_documents (updated_at DESC);
CREATE INDEX IF NOT EXISTS vault_documents_title_trgm_idx ON vault_documents USING gin (title gin_trgm_ops);
CREATE INDEX IF NOT EXISTS vault_documents_fm_idx         ON vault_documents USING gin (frontmatter);

-- =====================================================================
-- Chunks — content chunks + pgvector embeddings (768-dim, nomic-embed-text)
-- =====================================================================
CREATE TABLE IF NOT EXISTS vault_chunks (
    id           BIGSERIAL PRIMARY KEY,
    document_id  BIGINT NOT NULL REFERENCES vault_documents(id) ON DELETE CASCADE,
    chunk_index  INTEGER NOT NULL,
    content      TEXT NOT NULL,
    token_est    INTEGER NOT NULL DEFAULT 0,
    embedding    vector(768),                       -- NULL until indexer with embedding model runs
    UNIQUE (document_id, chunk_index)
);

-- IVFFlat is right for <1M vectors; switch to HNSW once we cross that threshold
CREATE INDEX IF NOT EXISTS vault_chunks_embedding_idx
    ON vault_chunks USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);

-- =====================================================================
-- Conversation events — timestamped session log
-- =====================================================================
CREATE TABLE IF NOT EXISTS conversation_events (
    id            BIGSERIAL PRIMARY KEY,
    session_id    TEXT NOT NULL,                    -- ULID or short hash, links to vault digest
    cwd           TEXT,                              -- working dir of the session
    started_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    ended_at      TIMESTAMPTZ,
    summary       TEXT,                              -- one-paragraph TL;DR
    digest_path   TEXT,                              -- relative path to 50-conversations/...md
    metadata      JSONB NOT NULL DEFAULT '{}'::jsonb -- model, token counts, tool calls, etc.
);

CREATE INDEX IF NOT EXISTS conversation_events_started_idx  ON conversation_events (started_at DESC);
CREATE INDEX IF NOT EXISTS conversation_events_session_idx  ON conversation_events (session_id);

-- =====================================================================
-- Entity mentions — extracted entities (people, services, projects, technologies)
-- Lets us answer "what did we discuss about k3s last month?"
-- =====================================================================
CREATE TABLE IF NOT EXISTS entity_mentions (
    id           BIGSERIAL PRIMARY KEY,
    entity_name  TEXT NOT NULL,
    entity_type  TEXT NOT NULL CHECK (entity_type IN ('person','project','service','technology','file','host','other')),
    document_id  BIGINT NOT NULL REFERENCES vault_documents(id) ON DELETE CASCADE,
    chunk_index  INTEGER,                            -- where in the doc, optional
    first_seen   TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (entity_name, entity_type, document_id)
);

CREATE INDEX IF NOT EXISTS entity_mentions_name_idx ON entity_mentions (lower(entity_name));
CREATE INDEX IF NOT EXISTS entity_mentions_type_idx ON entity_mentions (entity_type);

-- =====================================================================
-- Decisions index — flat ADR registry with supersedes chain
-- Mirrors 40-decisions/ frontmatter for fast queries
-- =====================================================================
CREATE TABLE IF NOT EXISTS decisions_index (
    id            BIGSERIAL PRIMARY KEY,
    decision_id   TEXT UNIQUE NOT NULL,             -- frontmatter `id`
    title         TEXT NOT NULL,
    status        TEXT NOT NULL CHECK (status IN ('active','superseded','draft')),
    decided_at    DATE NOT NULL,
    document_id   BIGINT NOT NULL REFERENCES vault_documents(id) ON DELETE CASCADE,
    supersedes    TEXT[] NOT NULL DEFAULT '{}',     -- array of decision_ids
    superseded_by TEXT                              -- decision_id, NULL if still active
);

CREATE INDEX IF NOT EXISTS decisions_index_status_idx     ON decisions_index (status);
CREATE INDEX IF NOT EXISTS decisions_index_decided_at_idx ON decisions_index (decided_at DESC);

-- =====================================================================
-- Convenience views
-- =====================================================================

-- Recent active conversations (what SessionStart hook reads)
CREATE OR REPLACE VIEW recent_conversations AS
    SELECT ce.session_id,
           ce.started_at,
           ce.summary,
           ce.digest_path,
           ce.cwd
    FROM conversation_events ce
    WHERE ce.summary IS NOT NULL
    ORDER BY ce.started_at DESC
    LIMIT 20;

-- Active project notes
CREATE OR REPLACE VIEW active_projects AS
    SELECT path, title, frontmatter, updated_at
    FROM vault_documents
    WHERE type = 'project' AND status = 'active'
    ORDER BY updated_at DESC;

-- Active decisions chain head
CREATE OR REPLACE VIEW active_decisions AS
    SELECT di.decision_id, di.title, di.decided_at, vd.path
    FROM decisions_index di
    JOIN vault_documents vd ON vd.id = di.document_id
    WHERE di.status = 'active'
    ORDER BY di.decided_at DESC;
