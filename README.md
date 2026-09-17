# NYC Street History

NYC Street History is a location-aware iPhone app backed by a FastAPI service.  
You open the app while walking around New York City, it reads your location, snaps you to the nearest street, and returns a card with:

- the street you are on
- the nearest cross street
- the neighborhood and borough
- a short historical fact
- nearby places like parks, transit, and food

The product goal is simple: make the city feel annotated.

## What It Actually Does

Here is the practical version.

If you stand on Broadway near Union Square, the app can:

- identify that you are on `Broadway`
- show the closest cross street
- tell you you are in `Midtown South-Flatiron-Union Square`
- surface a short historical note about Broadway if one exists
- fall back to a nearby place fact like `Union Square Park`
- show nearby places such as:
  - parks
  - subway stations
  - food

If you are walking around Williamsburg or Greenpoint, it can do the same for streets like:

- `Bedford Avenue`
- `Metropolitan Avenue`
- `Nassau Avenue`
- `Manhattan Avenue`
- `Franklin Street`

and places like:

- `McCarren Park`
- `Domino Park`
- `Transmitter Park`
- `Williamsburg Bridge`

The app is not trying to be a map.  
It is trying to answer: "what is the historical context of where I am standing right now?"

## What Is In This Repo

This repository has three main pieces:

1. `backend/`
   - FastAPI app
   - Postgres/PostGIS queries
   - data import scripts
   - tests

2. `ios/StreetHistory/`
   - SwiftUI iPhone app
   - Core Location integration
   - API client and card rendering

3. `infra/`
   - local Docker setup for running Postgres + API together

At the top level there is also:

- `render.yaml` for backend deployment on Render

## Current Product Scope

The app is currently optimized for:

- New York City only
- street-level location lookup
- named street facts
- place facts for parks / civic places when nearby
- nearby categories:
  - `park`
  - `transit`
  - `food`

Landmark coverage is still incomplete.  
Fact coverage is seeded and growing, not comprehensive yet.

## How It Works

### Backend request flow

`GET /v1/card?lat={lat}&lon={lon}&acc={accuracy}`

For each request, the backend:

1. snaps the GPS point to the nearest `street_segment`
2. looks up the containing neighborhood polygon
3. finds the nearest cross street
4. tries to find a fact in this order:
   - `street_code`
   - `street_name`
   - nearby `place_name`
   - neighborhood fallback text
5. returns nearby places ranked for relevance

### Example API response

```json
{
  "canonical_street": "Broadway",
  "cross_street": "East 14 Street",
  "borough": "Manhattan",
  "neighborhood": "Midtown South-Flatiron-Union Square",
  "mode": "NAMED_STREET",
  "did_you_know": "Broadway follows an older Native path through Manhattan and long predates the Commissioners' grid.",
  "nearby": [
    {
      "name": "Union Square Park",
      "category": "park",
      "distance_m": 222
    },
    {
      "name": "14 St-Union Sq",
      "category": "transit",
      "distance_m": 176
    },
    {
      "name": "Venchi",
      "category": "food",
      "distance_m": 8
    }
  ],
  "sources": [
    {
      "label": "Wikipedia",
      "url": "https://en.wikipedia.org/wiki/Broadway_(Manhattan)"
    }
  ]
}
```

### Example app scenarios

1. You are on `Houston Street` near `Chrystie Street`
   - the app should snap to Houston
   - return a Lower East Side neighborhood
   - show a Houston Street fact if loaded
   - list nearby transit and food

2. You are near `Union Square Park`
   - even if the street fact is missing, the backend can fall back to a `place_name` fact
   - this is how the app handles major civic spaces that matter more than the street itself

3. You are in `Greenpoint` on `Nassau Avenue`
   - the app can return Nassau Avenue or one of its cross streets
   - nearby places might include `McGolrick Park`, `Transmitter Park`, or subway stops
   - the fact layer is seeded specifically for this area

### iOS flow

The iOS app:

1. requests location permission
2. listens for movement updates
3. fetches a new card when the user moves enough to matter
4. keeps the last card cached locally
5. renders the result in SwiftUI

## Project Structure

### Backend

Important files:

- [backend/app/main.py](/Users/josephruocco/nyc-street-history/backend/app/main.py)
  - FastAPI routes
  - `/v1/card`
  - `/health`
  - `/health/poi`
  - `/health/facts`

- [backend/app/queries.py](/Users/josephruocco/nyc-street-history/backend/app/queries.py)
  - street snapping SQL
  - neighborhood SQL
  - nearby place ranking SQL
  - fact lookup SQL
  - cross-street lookup SQL

- [backend/app/settings.py](/Users/josephruocco/nyc-street-history/backend/app/settings.py)
  - environment-based configuration
  - cache TTL and geohash precision

- [backend/app/sql/init.sql](/Users/josephruocco/nyc-street-history/backend/app/sql/init.sql)
  - schema bootstrap

- [backend/scripts/import_poi_geojson.py](/Users/josephruocco/nyc-street-history/backend/scripts/import_poi_geojson.py)
  - loads normalized POIs into Postgres

- [backend/scripts/build_nyc_poi_geojson.py](/Users/josephruocco/nyc-street-history/backend/scripts/build_nyc_poi_geojson.py)
  - fetches and builds NYC POI data bundle

- [backend/scripts/poi_refresh.sh](/Users/josephruocco/nyc-street-history/backend/scripts/poi_refresh.sh)
  - rebuild + import + verify POIs

- [backend/scripts/import_facts_csv.py](/Users/josephruocco/nyc-street-history/backend/scripts/import_facts_csv.py)
  - bulk-upserts historical facts from CSV

- [backend/data/facts_seed.csv](/Users/josephruocco/nyc-street-history/backend/data/facts_seed.csv)
  - starter fact dataset for streets and places

### iOS

Important files:

- [ios/StreetHistory/StreetHistory/ContentView.swift](/Users/josephruocco/nyc-street-history/ios/StreetHistory/StreetHistory/ContentView.swift)
  - main card UI

- [ios/StreetHistory/StreetHistory/CardViewModel.swift](/Users/josephruocco/nyc-street-history/ios/StreetHistory/StreetHistory/CardViewModel.swift)
  - fetch/update logic
  - local card cache

- [ios/StreetHistory/StreetHistory/LocationManager.swift](/Users/josephruocco/nyc-street-history/ios/StreetHistory/StreetHistory/LocationManager.swift)
  - Core Location integration

- [ios/StreetHistory/StreetHistory/APIClient.swift](/Users/josephruocco/nyc-street-history/ios/StreetHistory/StreetHistory/APIClient.swift)
  - backend calls
  - reads `APIBaseURL`

- [ios/StreetHistory/StreetHistory/Models.swift](/Users/josephruocco/nyc-street-history/ios/StreetHistory/StreetHistory/Models.swift)
  - API response models

## Data Model

The backend depends on a few key tables:

- `street_segment`
  - source: NYC LION street geometry
  - used for street snapping

- `neighborhood`
  - source: NYNTA neighborhood polygons
  - used for neighborhood lookup

- `fact`
  - custom historical facts
  - supports:
    - `street_code`
    - `street_name`
    - `place_name`

- `poi`
  - nearby points of interest
  - currently normalized to:
    - `park`
    - `transit`
    - `food`
    - `landmark` support exists in code, but coverage is not complete

## Local Development

### Backend only

From repo root:

```bash
cd backend
set -a; source ../.env; set +a
python3 -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

Test it:

```bash
curl -s "http://127.0.0.1:8000/health"
curl -s "http://127.0.0.1:8000/v1/card?lat=40.7183&lon=-73.9579&acc=25" | python3 -m json.tool
```

### Local Docker stack

```bash
cd infra
docker compose up --build
```

This is mainly useful if you want a local Postgres/PostGIS stack instead of Supabase.

## Data Loading

### POIs

Build and import POIs:

```bash
bash backend/scripts/poi_refresh.sh
```

Optional category subset:

```bash
bash backend/scripts/poi_refresh.sh park,transit,food
```

### Historical facts

Import the seed facts:

```bash
set -a; source .env; set +a
python3 backend/scripts/import_facts_csv.py backend/data/facts_seed.csv
```

## Testing

Run backend tests:

```bash
cd backend
python3 -m unittest discover -s tests -v
```

The test suite currently covers:

- cache behavior
- cross-street SQL wiring
- POI query logic
- fact fallback behavior
- CSV fact importer behavior
- health endpoints

## Deployment

### Database

The production database is intended to live on Supabase using Postgres + PostGIS.

Required environment variable:

```env
DATABASE_URL=postgresql+psycopg://...
```

### Backend

The backend is configured for Render using [render.yaml](/Users/josephruocco/nyc-street-history/render.yaml).

Typical production checks:

```bash
curl -s "https://<your-service>/health" | python3 -m json.tool
curl -s "https://<your-service>/health/poi" | python3 -m json.tool
curl -s "https://<your-service>/health/facts" | python3 -m json.tool
curl -s "https://<your-service>/v1/card?lat=40.7183&lon=-73.9579&acc=25" | python3 -m json.tool
```

### iOS

Open [StreetHistory.xcodeproj](/Users/josephruocco/nyc-street-history/ios/StreetHistory/StreetHistory.xcodeproj) in Xcode and run the app on a real device.

The app reads `APIBaseURL` from build settings, so you can point Debug or Release at different backends without changing Swift code.

## Project Status

### What is working

- [x] FastAPI backend with `/v1/card`, `/health`, `/health/poi`, and `/health/facts` endpoints
- [x] Street snapping via PostGIS nearest-neighbour query
- [x] Neighborhood and borough lookup from NYNTA polygons
- [x] Cross-street detection
- [x] Fact lookup with fallback chain: `street_code` → `street_name` → `place_name` → neighbourhood text
- [x] POI categories: `park`, `transit`, `food`
- [x] 63 seed facts loaded (46 street facts, 17 place facts)
- [x] SwiftUI iOS app with Core Location integration, local card cache, and card rendering
- [x] Local Docker Compose stack for development
- [x] Render deployment config (`render.yaml`)
- [x] Test suite: 44 tests passing across 9 test files

### What is in progress

- [ ] Fact coverage — seeded facts cover around 60 streets and places; the vast majority of NYC is uncovered
- [ ] Place ranking — generic nearby food currently scores above major civic landmarks
- [ ] Landmark POI data — the `landmark` category is wired in the backend but not yet populated with real data

### What is planned

- [ ] CI pipeline — no GitHub Actions workflows; tests are run manually
- [ ] Automated data refresh — POI and fact import scripts exist but nothing schedules them
- [ ] Monitoring and structured logging beyond the health endpoints
- [ ] Rate limiting and authentication on the public API
- [ ] Offline mode for the iOS app beyond the single cached card

> **Note:** free Render instances sleep after inactivity, so the first request after idle may be slow.

## Short-Term Priorities

1. expand fact coverage in the neighborhoods you actually walk through
2. improve place ranking so major civic places beat generic nearby food
3. complete landmark ingestion
4. keep the iOS experience fast and legible while moving

## Why This Exists

Most city apps tell you where to go.  
This one is trying to tell you what the street under your feet means.
