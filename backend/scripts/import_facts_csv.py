#!/usr/bin/env python3
"""Import street facts from CSV into fact table.

CSV columns:
- key_type (required): street_code | street_name | place_name
- key_value (required)
- fact_text (required)
- namesake (optional)
- history_blurb (optional)
- image_url (optional)
- image_source_url (optional)
- source_label (optional)
- source_url (optional)
- confidence (optional, default 0.5)

Usage:
  DATABASE_URL=postgresql://... python3 backend/scripts/import_facts_csv.py path/to/facts.csv
"""

from __future__ import annotations

import csv
import os
import sys
from pathlib import Path

UPSERT_SQL = """
INSERT INTO fact (
  key_type,
  key_value,
  fact_text,
  namesake,
  history_blurb,
  image_url,
  image_source_url,
  source_label,
  source_url,
  confidence,
  updated_at
)
VALUES (
  %(key_type)s,
  %(key_value)s,
  %(fact_text)s,
  %(namesake)s,
  %(history_blurb)s,
  %(image_url)s,
  %(image_source_url)s,
  %(source_label)s,
  %(source_url)s,
  %(confidence)s,
  now()
)
ON CONFLICT (key_type, key_value, md5(fact_text))
DO UPDATE SET
  fact_text = EXCLUDED.fact_text,
  namesake = EXCLUDED.namesake,
  history_blurb = EXCLUDED.history_blurb,
  image_url = EXCLUDED.image_url,
  image_source_url = EXCLUDED.image_source_url,
  source_label = EXCLUDED.source_label,
  source_url = EXCLUDED.source_url,
  confidence = EXCLUDED.confidence,
  updated_at = now();
"""


def normalize_key(row: dict) -> tuple[str, str] | None:
    key_type = (row.get("key_type") or "").strip().lower()
    key_value = (row.get("key_value") or "").strip()

    if key_type not in {"street_code", "street_name", "place_name"}:
        return None
    if not key_value:
        return None

    if key_type in {"street_name", "place_name"}:
        key_value = " ".join(key_value.split()).lower()

    return key_type, key_value


def parse_confidence(raw: str | None) -> float:
    if raw is None or not raw.strip():
        return 0.5
    try:
        value = float(raw)
    except ValueError:
        return 0.5
    return max(0.0, min(1.0, value))


def row_to_params(row: dict) -> dict | None:
    key = normalize_key(row)
    if key is None:
        return None

    fact_text = (row.get("fact_text") or "").strip()
    if not fact_text:
        return None

    key_type, key_value = key
    namesake = (row.get("namesake") or "").strip() or None
    history_blurb = (row.get("history_blurb") or "").strip() or fact_text
    image_url = (row.get("image_url") or "").strip() or None
    image_source_url = (row.get("image_source_url") or "").strip() or None
    source_label = (row.get("source_label") or "").strip() or None
    source_url = (row.get("source_url") or "").strip() or None
    confidence = parse_confidence(row.get("confidence"))

    return {
        "key_type": key_type,
        "key_value": key_value,
        "fact_text": fact_text,
        "namesake": namesake,
        "history_blurb": history_blurb,
        "image_url": image_url,
        "image_source_url": image_source_url,
        "source_label": source_label,
        "source_url": source_url,
        "confidence": confidence,
    }


def ensure_unique_constraint(conn) -> None:
    with conn.cursor() as cur:
        cur.execute("ALTER TABLE fact ADD COLUMN IF NOT EXISTS namesake TEXT;")
        cur.execute("ALTER TABLE fact ADD COLUMN IF NOT EXISTS history_blurb TEXT;")
        cur.execute("ALTER TABLE fact ADD COLUMN IF NOT EXISTS image_url TEXT;")
        cur.execute("ALTER TABLE fact ADD COLUMN IF NOT EXISTS image_source_url TEXT;")
        # A street now holds several rotating facts, so the fact identity is the
        # text itself, not just the street. Re-importing the same fact upserts;
        # a new fact for the same street adds a row.
        cur.execute("DROP INDEX IF EXISTS uq_fact_key_type_value;")
        cur.execute(
            """
            CREATE UNIQUE INDEX IF NOT EXISTS uq_fact_key_value_text
            ON fact (key_type, key_value, md5(fact_text));
            """
        )
    conn.commit()


def main() -> int:
    import psycopg  # local import so parser tests can run without DB deps

    if len(sys.argv) != 2:
        print("Usage: import_facts_csv.py path/to/facts.csv", file=sys.stderr)
        return 2

    db_url = os.getenv("DATABASE_URL")
    if not db_url:
        print("DATABASE_URL is required", file=sys.stderr)
        return 2
    if db_url.startswith("postgresql+psycopg://"):
        db_url = db_url.replace("postgresql+psycopg://", "postgresql://", 1)

    csv_path = Path(sys.argv[1])
    with csv_path.open("r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        params = []
        skipped = 0
        for row in reader:
            parsed = row_to_params(row)
            if parsed is None:
                skipped += 1
                continue
            params.append(parsed)

    with psycopg.connect(db_url) as conn:
        ensure_unique_constraint(conn)
        with conn.cursor() as cur:
            if params:
                cur.executemany(UPSERT_SQL, params)
        conn.commit()

    print(f"Upserted {len(params)} facts, skipped {skipped} rows")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
