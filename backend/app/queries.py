# backend/app/queries.py

from __future__ import annotations

import re
from typing import Any, Dict, List, Optional, Tuple

from sqlalchemy import text
from sqlalchemy.orm import Session

# If your db.py exposes get_session() or SessionLocal, use that.
# We'll support both patterns:
try:
    from .db import SessionLocal  # type: ignore
except Exception:
    SessionLocal = None  # type: ignore

try:
    from .db import get_session  # type: ignore
except Exception:
    get_session = None  # type: ignore


# -----------------------------
# SQL
# -----------------------------

SNAP_STREET_SQL = """
WITH p AS (
  SELECT ST_SetSRID(ST_MakePoint(:lon, :lat), 4326) AS pt
)
SELECT
  id,
  street_code,
  primary_name,
  borough,
  ROUND(ST_Distance(geom::geography, p.pt::geography))::int AS dist_m
FROM street_segment, p
WHERE ST_DWithin(geom::geography, p.pt::geography, :radius_m)
ORDER BY ST_Distance(geom::geography, p.pt::geography)
LIMIT 1;
"""

NEIGHBORHOOD_SQL = """
SELECT name
FROM neighborhood
WHERE ST_Contains(geom, ST_SetSRID(ST_MakePoint(:lon, :lat), 4326))
LIMIT 1;
"""

NEARBY_POI_SQL = """
WITH p AS (
  SELECT ST_SetSRID(ST_MakePoint(:lon, :lat), 4326)::geography AS g
),
candidates AS (
  SELECT
    name,
    CASE
      WHEN LOWER(category) IN ('park', 'playground', 'garden') THEN 'park'
      WHEN LOWER(category) IN ('landmark', 'historic', 'museum', 'monument') THEN 'landmark'
      WHEN LOWER(category) IN ('transit', 'subway', 'bus', 'train', 'ferry') THEN 'transit'
      WHEN LOWER(category) IN ('food', 'restaurant', 'cafe', 'bar', 'bakery') THEN 'food'
      ELSE NULL
    END AS category,
    rank_score,
    ST_Distance(geom::geography, p.g) AS dist_m
  FROM poi, p
  WHERE ST_DWithin(geom::geography, p.g, :radius_m)
),
scored AS (
  SELECT
    name,
    category,
    dist_m,
    (
      (rank_score * 1000.0) - dist_m
      + CASE
          WHEN category IN ('landmark', 'park') AND dist_m <= 250 THEN 2500
          WHEN category = 'transit' AND dist_m <= 150 THEN 800
          WHEN category = 'food' AND dist_m <= 60 THEN 350
          ELSE 0
        END
    ) AS score,
    CASE category
      WHEN 'landmark' THEN 1
      WHEN 'park' THEN 2
      WHEN 'transit' THEN 3
      WHEN 'food' THEN 4
      ELSE 5
    END AS category_priority
  FROM candidates
  WHERE category IS NOT NULL
),
ranked AS (
  SELECT
    name,
    category,
    dist_m,
    score,
    category_priority,
    ROW_NUMBER() OVER (
      PARTITION BY category
      ORDER BY score DESC
    ) AS category_rank
  FROM scored
)
SELECT
  name,
  category,
  ROUND(dist_m)::int AS distance_m
FROM ranked
ORDER BY
  category_rank,
  category_priority,
  score DESC
LIMIT :limit_n;
"""

FACT_BY_STREETCODE_SQL = """
SELECT to_jsonb(fact) AS fact
FROM fact
WHERE key_type = 'street_code' AND key_value = :street_code
ORDER BY confidence DESC, updated_at DESC
LIMIT 1;
"""

FACT_BY_STREETNAME_SQL = """
SELECT to_jsonb(fact) AS fact
FROM fact
WHERE key_type = 'street_name' AND LOWER(BTRIM(key_value)) = :street_name
ORDER BY confidence DESC, updated_at DESC
LIMIT 1;
"""

FACT_BY_PLACENAME_SQL = """
SELECT to_jsonb(fact) AS fact
FROM fact
WHERE key_type = 'place_name' AND LOWER(BTRIM(key_value)) = :place_name
ORDER BY confidence DESC, updated_at DESC
LIMIT 1;
"""

FACTS_MAP_SQL = """
SELECT
  f.key_value AS street_name,
  f.fact_text,
  f.namesake,
  f.source_label,
  f.source_url,
  f.confidence,
  s.borough,
  n.name AS neighborhood,
  -- ponytail: intrinsic rarity, not crowd data. Courts/lanes/walks and very
  -- short segments are the genuinely obscure streets; upgrade to real
  -- exploration counts if accounts ever exist.
  CASE
    WHEN s.primary_name ~* '(lane|court|walk|alley|mews|row|slip)$' THEN 'rare'
    WHEN ST_Length(s.geom::geography) < 350 THEN 'uncommon'
    ELSE 'common'
  END AS rarity,
  ST_Y(ST_Centroid(s.geom)) AS lat,
  ST_X(ST_Centroid(s.geom)) AS lon
FROM fact f
JOIN LATERAL (
  SELECT geom, borough, primary_name
  FROM street_segment
  WHERE LOWER(BTRIM(primary_name)) = LOWER(BTRIM(f.key_value))
  LIMIT 1
) s ON true
LEFT JOIN LATERAL (
  SELECT name
  FROM neighborhood
  WHERE ST_Contains(geom, ST_Centroid(s.geom))
  LIMIT 1
) n ON true
WHERE f.key_type = 'street_name'
  AND f.confidence >= :min_confidence
ORDER BY f.key_value;
"""

CROSS_STREET_SQL = """
WITH main AS (
  SELECT id, primary_name, geom
  FROM street_segment
  WHERE id = :segment_id
),
user_p AS (
  SELECT ST_SetSRID(ST_MakePoint(:lon, :lat), 4326) AS pt
),
candidates AS (
  SELECT
    s.id,
    s.primary_name,
    s.borough,
    ST_ClosestPoint(ST_Intersection(s.geom, m.geom), u.pt) AS ix_point,
    u.pt AS user_pt
  FROM street_segment s
  JOIN main m ON s.id <> m.id
  CROSS JOIN user_p u
  WHERE s.primary_name IS NOT NULL
    AND ST_Intersects(s.geom, m.geom)
    AND UPPER(BTRIM(s.primary_name)) <> UPPER(BTRIM(m.primary_name))
)
SELECT
  id,
  primary_name,
  borough
FROM candidates
ORDER BY
  ST_Distance(ix_point::geography, user_pt::geography),
  id
LIMIT 1;
"""

# -----------------------------
# Street name classification
# -----------------------------

_NUMBERED_PATTERNS = [
    # "14 St", "14th St", "14 Street", "14th Street"
    re.compile(r"^\s*\d+\s*(st|nd|rd|th)?\s+(st|street)\b", re.I),
    # "E 14 St", "W 4th St", "East 14th Street"
    re.compile(r"^\s*(e|w|n|s|east|west|north|south)\s+\d+\s*(st|nd|rd|th)?\s+(st|street)\b", re.I),
    # numbered avenues: "1 Ave", "1st Ave", "2 Avenue"
    re.compile(r"^\s*\d+\s*(st|nd|rd|th)?\s+(ave|avenue)\b", re.I),
    # "Ave A", "Avenue B"
    re.compile(r"^\s*(ave|avenue)\s+[a-z]\b", re.I),
]

def is_numbered_or_lettered_street(name: Optional[str]) -> bool:
    if not name:
        return False
    s = name.strip()
    return any(p.search(s) for p in _NUMBERED_PATTERNS)


# -----------------------------
# Session helper
# -----------------------------

def _open_session() -> Session:
    """
    Returns a SQLAlchemy Session.
    Supports either:
      - db.get_session() -> context manager / generator
      - db.SessionLocal() -> Session
    """
    if get_session is not None:
        # If get_session is a generator (FastAPI dependency), we can pull one.
        s = get_session()
        # common pattern: yield session; here s is a generator
        if hasattr(s, "__next__"):
            return next(s)  # type: ignore
        return s  # type: ignore

    if SessionLocal is not None:
        return SessionLocal()  # type: ignore

    raise RuntimeError("Could not create DB session: expected get_session or SessionLocal in db.py")


# -----------------------------
# Query functions
# -----------------------------

def snap_street(
    db: Session,
    lat: float,
    lon: float,
    radius_m: int,
) -> Optional[Dict[str, Any]]:
    row = db.execute(
        text(SNAP_STREET_SQL),
        {"lat": lat, "lon": lon, "radius_m": radius_m},
    ).mappings().first()

    return dict(row) if row else None


def get_neighborhood(
    db: Session,
    lat: float,
    lon: float,
) -> Optional[str]:
    row = db.execute(
        text(NEIGHBORHOOD_SQL),
        {"lat": lat, "lon": lon},
    ).first()
    return row[0] if row else None


def get_nearby_pois(
    db: Session,
    lat: float,
    lon: float,
    radius_m: int,
    limit_n: int,
) -> List[Dict[str, Any]]:
    rows = db.execute(
        text(NEARBY_POI_SQL),
        {"lat": lat, "lon": lon, "radius_m": radius_m, "limit_n": limit_n},
    ).mappings().all()
    return [dict(r) for r in rows]


def get_fact_for_street_code(
    db: Session,
    street_code: str,
) -> Optional[Dict[str, Any]]:
    row = db.execute(
        text(FACT_BY_STREETCODE_SQL),
        {"street_code": street_code},
    ).mappings().first()
    return dict(row) if row else None


def build_card(
    db: Session,
    lat: float,
    lon: float,
    acc: float,
    *,
    snap_radius_floor_m: int = 25,
    snap_radius_cap_m: int = 250,
    poi_radius_m: int = 600,
    poi_limit_n: int = 8,
) -> Dict[str, Any]:
    """
    Builds the API response for /v1/card.

    - Snap to nearest street segment within a radius derived from accuracy.
    - Find containing neighborhood.
    - Fetch nearby POIs.
    - Only include "did_you_know" for named streets (not numbered/lettered).
    """
    radius_m = int(max(snap_radius_floor_m, min(snap_radius_cap_m, acc * 2.0)))

    snapped = snap_street(db, lat=lat, lon=lon, radius_m=radius_m)
    neighborhood = get_neighborhood(db, lat=lat, lon=lon)
    nearby = get_nearby_pois(db, lat=lat, lon=lon, radius_m=poi_radius_m, limit_n=poi_limit_n)

    canonical_street = snapped["primary_name"] if snapped else None
    borough = snapped["borough"] if snapped else None
    street_code = snapped["street_code"] if snapped else None
    dist_m = snapped["dist_m"] if snapped else None

    did_you_know = None
    fact_source_label = None
    fact_source_url = None
    fact_confidence = None

    mode = "nearby"
    if canonical_street and not is_numbered_or_lettered_street(canonical_street) and street_code:
        mode = "named"
        fact = get_fact_for_street_code(db, street_code=street_code)
        if fact:
            did_you_know = fact.get("fact_text")
            fact_source_label = fact.get("source_label")
            fact_source_url = fact.get("source_url")
            fact_confidence = fact.get("confidence")

    return {
        "canonical_street": canonical_street,
        "borough": borough,
        "neighborhood": neighborhood,
        "mode": mode,
        "snap_distance_m": dist_m,
        "did_you_know": did_you_know,
        "fact_source_label": fact_source_label,
        "fact_source_url": fact_source_url,
        "fact_confidence": fact_confidence,
        "nearby": nearby,
    }


# Convenience wrapper if you want to call without passing a Session
def build_card_autosession(lat: float, lon: float, acc: float) -> Dict[str, Any]:
    db = _open_session()
    try:
        return build_card(db, lat=lat, lon=lon, acc=acc)
    finally:
        db.close()
