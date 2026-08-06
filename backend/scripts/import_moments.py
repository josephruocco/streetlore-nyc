"""Seed "moments": viral NYC happenings tied to a spot, surfaced when you walk
near them. Stored in the fact table as key_type='moment' with their own lat/lon
and a trigger radius, so they survive POI refreshes (which TRUNCATE the poi
table). Re-runnable: upserts on (key_type, key_value, md5(fact_text)).

    DATABASE_URL=... python3 backend/scripts/import_moments.py
"""
import sys
from app.db import execute, fetch_all

# name, lat, lon, radius_m, blurb, namesake, source_label, source_url
MOMENTS = [
    (
        "Timothée Chalamet Lookalike Contest",
        40.7308, -73.9973, 150,
        "In October 2024 thousands packed Washington Square Park for a Timothee "
        "Chalamet lookalike contest dreamed up by YouTuber Anthony Po. Police broke "
        "it up and issued a 500 dollar fine for an unpermitted contest, but not "
        "before Chalamet himself turned up in the crowd. A Staten Island college "
        "student, Miles Mitchell, was crowned the winner.",
        "Anthony Po", "Gothamist",
        "https://gothamist.com/arts-entertainment/timothée-chalamet-surprises-fans-at-nyc-look-alike-contest-winner-crowned",
    ),
    (
        "The Cheeseball Man",
        40.7359, -73.9911, 120,
        "In April 2024 an anonymous man in a bright orange ski mask drew a cheering "
        "crowd to Union Square to eat an entire jumbo jar of cheese balls. Promoted "
        "only through flyers and the TikTok handle cheeseballman427, the stunt turned "
        "a jar of snacks into a piece of New York folklore.",
        "The Cheeseball Man", "New York Post",
        "https://nypost.com/",
    ),
    (
        "The Bed-Stuy Aquarium",
        40.6839, -73.9436, 90,
        "In the summer of 2024 neighbors turned a tree pit flooded by a leaky hydrant "
        "at Hancock Street and Tompkins Avenue into the Bed-Stuy Aquarium, releasing "
        "goldfish into the pooling water. Started by resident Hajj-Malik Lovick, it "
        "survived vandalism and a city crew that paved it over before the community "
        "rebuilt it with a solar powered filter.",
        "Hajj-Malik Lovick", "NBC New York",
        "https://www.nbcnewyork.com/brooklyn/bed-stuy-aquarium-leaky-brooklyn-hydrant-reborn-tree-bed/5946060/",
    ),
]

UPSERT = """
INSERT INTO fact (key_type, key_value, fact_text, namesake, history_blurb,
                  source_label, source_url, confidence, lat, lon, radius_m, updated_at)
VALUES ('moment', :name, :blurb, :namesake, :blurb,
        :source_label, :source_url, 0.9, :lat, :lon, :radius_m, now())
ON CONFLICT (key_type, key_value, md5(fact_text))
DO UPDATE SET namesake = EXCLUDED.namesake,
              history_blurb = EXCLUDED.history_blurb,
              source_label = EXCLUDED.source_label,
              source_url = EXCLUDED.source_url,
              lat = EXCLUDED.lat, lon = EXCLUDED.lon,
              radius_m = EXCLUDED.radius_m, updated_at = now();
"""


def main() -> int:
    # Columns a moment needs beyond the base fact schema.
    for ddl in (
        "ALTER TABLE fact ADD COLUMN IF NOT EXISTS lat REAL",
        "ALTER TABLE fact ADD COLUMN IF NOT EXISTS lon REAL",
        "ALTER TABLE fact ADD COLUMN IF NOT EXISTS radius_m INTEGER",
    ):
        execute(ddl)

    for name, lat, lon, radius_m, blurb, namesake, label, url in MOMENTS:
        execute(UPSERT, {
            "name": name, "blurb": blurb, "namesake": namesake,
            "source_label": label, "source_url": url,
            "lat": lat, "lon": lon, "radius_m": radius_m,
        })

    n = fetch_all("SELECT count(*) AS n FROM fact WHERE key_type='moment'", {})[0]["n"]
    print(f"Seeded moments. Total moments now: {n}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
