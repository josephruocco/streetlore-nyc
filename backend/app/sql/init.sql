CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TABLE IF NOT EXISTS street_segment (
  id BIGSERIAL PRIMARY KEY,
  street_code TEXT,
  primary_name TEXT,
  borough TEXT,
  geom geometry(LineString, 4326)
);

CREATE INDEX IF NOT EXISTS idx_street_segment_geom
  ON street_segment USING gist (geom);

CREATE TABLE IF NOT EXISTS neighborhood (
  id BIGSERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  geom geometry(MultiPolygon, 4326)
);

CREATE INDEX IF NOT EXISTS idx_neighborhood_geom
  ON neighborhood USING gist (geom);

CREATE TABLE IF NOT EXISTS poi (
  id BIGSERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  category TEXT NOT NULL,
  rank_score REAL NOT NULL DEFAULT 1.0,
  geom geometry(Point, 4326)
);

CREATE INDEX IF NOT EXISTS idx_poi_geom
  ON poi USING gist (geom);

CREATE TABLE IF NOT EXISTS fact (
  id BIGSERIAL PRIMARY KEY,
  key_type TEXT NOT NULL,
  key_value TEXT NOT NULL,
  fact_text TEXT NOT NULL,
  namesake TEXT,
  history_blurb TEXT,
  image_url TEXT,
  image_source_url TEXT,
  source_label TEXT,
  source_url TEXT,
  confidence REAL NOT NULL DEFAULT 0.5,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_fact_key
  ON fact (key_type, key_value);
