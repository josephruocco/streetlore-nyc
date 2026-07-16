import re
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from .cache import SimpleTTLCache, encode_geohash
from .db import fetch_one, fetch_all
from .models import CardResponse, NearbyItem, Source, HistoryEntry, FactMapItem
from .settings import settings
from .queries import (
    SNAP_STREET_SQL,
    NEIGHBORHOOD_SQL,
    NEARBY_POI_SQL,
    FACT_BY_STREETCODE_SQL,
    FACT_BY_STREETNAME_SQL,
    FACT_BY_PLACENAME_SQL,
    CROSS_STREET_SQL,
    FACTS_MAP_SQL,
    is_numbered_or_lettered_street,
)

app = FastAPI(title="NYC Street History API")

# Allow the browser-based explore page (and the marketing site) to call the API.
# ponytail: read-only public GET endpoints, so a permissive origin list is fine.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET"],
    allow_headers=["*"],
)

ORDINAL_PAT = re.compile(r"^(\d+)(ST|ND|RD|TH)$", re.IGNORECASE)

# Served for numbered/lettered streets with no specific fact row.
GRID_FACT_SOURCE = Source(
    label="Wikipedia",
    url="https://en.wikipedia.org/wiki/Commissioners%27_Plan_of_1811",
)
GRID_FACTS = {
    "manhattan": (
        "Commissioners' Plan of 1811",
        "The number here comes from the Commissioners' Plan of 1811, the survey that stamped a single grid of numbered streets and avenues across Manhattan above Houston Street. Surveyor John Randel Jr. spent nearly a decade planting marble markers at every future corner, dodging dogs, lawsuits, and angry farmers whose orchards sat in the path of the streets to come.",
    ),
    "bronx": (
        "Commissioners' Plan of 1811, extended north",
        "Bronx street numbers continue Manhattan's grid across the Harlem River. When the city annexed the Bronx in 1874 and 1895, the numbering of the Commissioners' Plan of 1811 simply kept counting northward, which is why the borough starts in the 130s instead of at 1.",
    ),
    "queens": (
        "The 1920s Queens renumbering (Philadelphia Plan)",
        "Queens street numbers come from the borough wide renumbering of the 1920s, often called the Philadelphia Plan. It replaced a patchwork of duplicate village street names with one numbered grid, and it is why a Queens address also tells you the nearest cross street.",
    ),
    "brooklyn": (
        "Brooklyn's 19th century street grids",
        "Brooklyn's numbered streets come from the separate grids of the old city of Brooklyn and its neighboring towns, laid out in the 19th century and stitched together when the borough joined New York City in 1898. That patchwork is why Brooklyn has plain, North, South, East, West, and Bay numbered streets that never quite line up.",
    ),
}
GRID_FACT_DEFAULT = (
    "The street grid",
    "Numbered streets like this one were laid out by 19th and early 20th century surveyors who favored grids because straight streets and right angles were the cheapest to build, sell, and navigate.",
)
NAMED_FOR_PATTERNS = [
    re.compile(r"\b(?:is|was)\s+named\s+for\s+([^.,;]+)", re.IGNORECASE),
    re.compile(r"\b(?:is|was)\s+named\s+after\s+([^.,;]+)", re.IGNORECASE),
    re.compile(r"\bhonors\s+([^.,;]+)", re.IGNORECASE),
    re.compile(r"\btakes\s+its\s+name\s+from\s+([^.,;]+)", re.IGNORECASE),
]
CARD_CACHE_TTL_SECONDS = max(0, int(settings.card_cache_ttl_seconds))
CARD_CACHE_PRECISION = min(12, max(1, int(settings.card_cache_precision)))
CARD_CACHE = SimpleTTLCache()
POI_TOTAL_SQL = "SELECT COUNT(*)::int AS total FROM poi;"
POI_COUNTS_SQL = """
SELECT category, COUNT(*)::int AS n
FROM poi
GROUP BY category
ORDER BY category;
"""
FACT_TOTAL_SQL = "SELECT COUNT(*)::int AS total FROM fact;"
FACT_COUNTS_SQL = """
SELECT key_type, COUNT(*)::int AS n
FROM fact
GROUP BY key_type
ORDER BY key_type;
"""


def prettify_street_name(name: str | None) -> str | None:
    if not name:
        return name

    words = name.strip().split()
    out = []
    directional_map = {
        "N": "North",
        "S": "South",
        "E": "East",
        "W": "West",
        "NE": "Northeast",
        "NW": "Northwest",
        "SE": "Southeast",
        "SW": "Southwest",
    }

    for w in words:
        upper = w.upper()
        ordinal_match = ORDINAL_PAT.match(upper)

        if ordinal_match:
            out.append(f"{ordinal_match.group(1)}{ordinal_match.group(2).lower()}")
        elif upper in directional_map:
            out.append(directional_map[upper])
        elif upper in {"ST", "AVE", "AV", "RD", "DR", "PL", "CT", "BLVD", "PKWY", "TER", "LN", "WAY"}:
            out.append(upper.title())
        elif upper.isdigit():
            out.append(upper)
        else:
            out.append(upper.title())

    return " ".join(out)

def classify_mode(street_name: str | None) -> str:
    if not street_name:
        return "NEAR"
    if is_numbered_or_lettered_street(street_name):
        return "NUMBERED_STREET"
    return "NAMED_STREET"


def normalize_fact_street_name(street_name: str | None) -> str | None:
    if not street_name:
        return None
    normalized = " ".join(street_name.strip().split()).lower()
    return normalized if normalized else None


def normalize_fact_place_name(place_name: str | None) -> str | None:
    if not place_name:
        return None
    normalized = " ".join(place_name.strip().split()).lower()
    return normalized if normalized else None


def extract_fact_payload(row: dict | None) -> dict | None:
    if not row:
        return None
    payload = row.get("fact")
    return payload if isinstance(payload, dict) else row


def infer_namesake(text: str | None) -> str | None:
    if not text:
        return None
    for pattern in NAMED_FOR_PATTERNS:
        match = pattern.search(text)
        if match:
            candidate = " ".join(match.group(1).split()).strip()
            return candidate.rstrip(" .,:;") or None
    return None


@app.get("/v1/card", response_model=CardResponse)
def card(lat: float, lon: float, acc: float = 25.0):
    cache_key = f"card:{encode_geohash(lat, lon, precision=CARD_CACHE_PRECISION)}"
    cached = CARD_CACHE.get(cache_key)
    if cached is not None:
        return CardResponse(**cached)

    radius_m = max(40, min(int(acc * 2.0), 120))

    street = fetch_one(SNAP_STREET_SQL, {"lat": lat, "lon": lon, "radius_m": radius_m})
    if not street:
        raise HTTPException(status_code=404, detail="No street segment found nearby")
    cross = fetch_one(CROSS_STREET_SQL, {"segment_id": street["id"], "lat": lat, "lon": lon})

    neighborhood = fetch_one(NEIGHBORHOOD_SQL, {"lat": lat, "lon": lon})
    nearby = fetch_all(NEARBY_POI_SQL, {"lat": lat, "lon": lon, "radius_m": 800, "limit_n": 6})

    mode = classify_mode(street.get("primary_name"))
    did_you_know = None
    namesake = None
    history_blurb = None
    image_url = None
    image_source_url = None
    sources: list[Source] = []

    if mode in ("NAMED_STREET", "NUMBERED_STREET"):
        fact = None

        if street.get("street_code"):
            fact = fetch_one(FACT_BY_STREETCODE_SQL, {"street_code": street["street_code"]})

        if not fact:
            normalized_street = normalize_fact_street_name(prettify_street_name(street.get("primary_name")))
            if normalized_street:
                fact = fetch_one(FACT_BY_STREETNAME_SQL, {"street_name": normalized_street})

        fact = extract_fact_payload(fact)

        if fact:
            history_blurb = fact.get("history_blurb") or fact.get("fact_text")
            did_you_know = history_blurb
            namesake = fact.get("namesake") or infer_namesake(history_blurb)
            image_url = fact.get("image_url")
            image_source_url = fact.get("image_source_url")
            sources.append(Source(label=fact.get("source_label") or "source", url=fact.get("source_url")))

    if not did_you_know and mode == "NUMBERED_STREET":
        borough_key = (street.get("borough") or "").strip().lower()
        namesake, history_blurb = GRID_FACTS.get(borough_key, GRID_FACT_DEFAULT)
        did_you_know = history_blurb
        sources.append(GRID_FACT_SOURCE)

    if not did_you_know:
        history_blurb = f"Street history for {prettify_street_name(street.get('primary_name'))} is still being researched."
        did_you_know = history_blurb

    response = CardResponse(
        canonical_street=prettify_street_name(street.get("primary_name")),
        cross_street=prettify_street_name(cross.get("primary_name")) if cross else None,
        borough=street.get("borough"),
        neighborhood=neighborhood["name"] if neighborhood else None,
        mode=mode,
        history=HistoryEntry(
            namesake=namesake,
            blurb=history_blurb,
            image_url=image_url,
            image_source_url=image_source_url,
            source=sources[0] if sources else None,
        ),
        namesake=namesake,
        history_blurb=history_blurb,
        image_url=image_url,
        image_source_url=image_source_url,
        did_you_know=did_you_know,
        nearby=[NearbyItem(**n) for n in nearby],
        sources=sources,
    )
    if CARD_CACHE_TTL_SECONDS > 0:
        if hasattr(response, "model_dump"):
            CARD_CACHE.set(cache_key, response.model_dump(), ttl_seconds=CARD_CACHE_TTL_SECONDS)
        else:
            CARD_CACHE.set(cache_key, response.dict(), ttl_seconds=CARD_CACHE_TTL_SECONDS)
    return response

@app.get("/v1/facts/map", response_model=list[FactMapItem])
def facts_map(min_confidence: float = 0.0):
    rows = fetch_all(FACTS_MAP_SQL, {"min_confidence": min_confidence})
    return [FactMapItem(**r) for r in rows]


@app.get("/health")
def health():
    return {"ok": True}


@app.get("/health/poi")
def health_poi():
    total_row = fetch_one(POI_TOTAL_SQL, {}) or {"total": 0}
    category_rows = fetch_all(POI_COUNTS_SQL, {})
    by_category = {row["category"]: row["n"] for row in category_rows}
    return {"ok": True, "poi": {"total": total_row["total"], "by_category": by_category}}


@app.get("/health/facts")
def health_facts():
    total_row = fetch_one(FACT_TOTAL_SQL, {}) or {"total": 0}
    key_type_rows = fetch_all(FACT_COUNTS_SQL, {})
    by_key_type = {row["key_type"]: row["n"] for row in key_type_rows}
    return {"ok": True, "facts": {"total": total_row["total"], "by_key_type": by_key_type}}
