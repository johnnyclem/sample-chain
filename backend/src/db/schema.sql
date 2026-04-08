-- SampleChain PostgreSQL Schema

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Creators table
CREATE TABLE IF NOT EXISTS creators (
  address       VARCHAR(42) PRIMARY KEY,
  display_name  VARCHAR(100),
  bio           TEXT,
  avatar_url    TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Samples table
CREATE TABLE IF NOT EXISTS samples (
  id              SERIAL PRIMARY KEY,
  token_id        INTEGER UNIQUE NOT NULL,
  creator_address VARCHAR(42) NOT NULL REFERENCES creators(address),
  ipfs_cid        VARCHAR(100) NOT NULL,
  title           VARCHAR(200) NOT NULL,
  description     TEXT,
  bpm             SMALLINT CHECK (bpm > 0 AND bpm < 999),
  musical_key     VARCHAR(10),
  sample_type     VARCHAR(20) NOT NULL CHECK (sample_type IN ('one-shot', 'loop', 'stem', 'full-track')),
  license_tier    VARCHAR(20) NOT NULL CHECK (license_tier IN ('free', 'basic', 'premium', 'exclusive')),
  price_wei       NUMERIC(78, 0) NOT NULL DEFAULT 0,
  edition_count   INTEGER NOT NULL DEFAULT 0,
  edition_limit   INTEGER,
  genre           VARCHAR(50),
  instrument_type VARCHAR(50),
  waveform_data   JSONB,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_samples_creator ON samples(creator_address);
CREATE INDEX idx_samples_genre ON samples(genre);
CREATE INDEX idx_samples_instrument ON samples(instrument_type);
CREATE INDEX idx_samples_bpm ON samples(bpm);
CREATE INDEX idx_samples_key ON samples(musical_key);
CREATE INDEX idx_samples_type ON samples(sample_type);
CREATE INDEX idx_samples_license ON samples(license_tier);
CREATE INDEX idx_samples_created ON samples(created_at DESC);

-- Full-text search index
ALTER TABLE samples ADD COLUMN IF NOT EXISTS search_vector tsvector
  GENERATED ALWAYS AS (
    setweight(to_tsvector('english', coalesce(title, '')), 'A') ||
    setweight(to_tsvector('english', coalesce(description, '')), 'B') ||
    setweight(to_tsvector('english', coalesce(genre, '')), 'C') ||
    setweight(to_tsvector('english', coalesce(instrument_type, '')), 'C')
  ) STORED;

CREATE INDEX idx_samples_search ON samples USING GIN(search_vector);

-- Sales table
CREATE TABLE IF NOT EXISTS sales (
  id              SERIAL PRIMARY KEY,
  token_id        INTEGER NOT NULL REFERENCES samples(token_id),
  buyer_address   VARCHAR(42) NOT NULL,
  seller_address  VARCHAR(42) NOT NULL,
  price_wei       NUMERIC(78, 0) NOT NULL,
  tx_hash         VARCHAR(66) UNIQUE NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_sales_token ON sales(token_id);
CREATE INDEX idx_sales_buyer ON sales(buyer_address);
CREATE INDEX idx_sales_seller ON sales(seller_address);
CREATE INDEX idx_sales_created ON sales(created_at DESC);

-- Favorites table
CREATE TABLE IF NOT EXISTS favorites (
  user_address VARCHAR(42) NOT NULL,
  token_id     INTEGER NOT NULL REFERENCES samples(token_id),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_address, token_id)
);

CREATE INDEX idx_favorites_user ON favorites(user_address);
CREATE INDEX idx_favorites_token ON favorites(token_id);

-- Updated-at trigger
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER samples_updated_at
  BEFORE UPDATE ON samples
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at();
