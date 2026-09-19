"""Import pilot street-fact research (scratchpad/pilot_*.json) into the fact table
and append to facts_seed.csv so it stays versioned. Idempotent: re-runnable as
more borough files land. Only imports found facts at/above a confidence floor.
"""
import csv, glob, json, os, re, sys
from app.db import execute, fetch_all

HARVEST = "data/harvest"   # in-repo, durable across session restarts
CSV = "data/facts_seed.csv"
MIN_CONF = 0.6

UPSERT = """
INSERT INTO fact (key_type, key_value, fact_text, namesake, history_blurb,
                  source_label, source_url, confidence, updated_at)
VALUES ('street_name', :kv, :fact, :namesake, :fact, :label, :url, :conf, now())
ON CONFLICT (key_type, key_value, md5(fact_text)) DO UPDATE SET
  namesake=EXCLUDED.namesake, history_blurb=EXCLUDED.history_blurb,
  source_label=EXCLUDED.source_label, source_url=EXCLUDED.source_url,
  confidence=EXCLUDED.confidence, updated_at=now();
"""


def clean(s):
    return re.sub(r"\s+", " ", (s or "").strip())


def main():
    rows = []
    for path in sorted(glob.glob(f"{HARVEST}/*.json")):
        try:
            data = json.load(open(path))
        except Exception as e:
            print(f"skip {os.path.basename(path)}: {e}")
            continue
        for r in data:
            if not r.get("found"):
                continue
            if (r.get("confidence") or 0) < MIN_CONF:
                continue
            fact = clean(r.get("fact"))
            if len(fact) < 25 or "—" in fact or "–" in fact:
                continue
            rows.append({
                "kv": clean(r["street"]).lower(),
                "fact": fact,
                "namesake": clean(r.get("namesake")) or None,
                "label": clean(r.get("source_label")) or "source",
                "url": clean(r.get("source_url")) or None,
                "conf": float(r.get("confidence") or 0.7),
            })

    # Dedupe by (street, fact)
    seen, uniq = set(), []
    for r in rows:
        k = (r["kv"], r["fact"])
        if k in seen:
            continue
        seen.add(k); uniq.append(r)

    # Upsert to DB
    for r in uniq:
        execute(UPSERT, r)

    # Append to CSV (only rows not already present by key+text)
    existing = set()
    with open(CSV) as f:
        for row in csv.DictReader(f):
            existing.add((row["key_value"], (row["fact_text"] or "")[:60]))
    added = 0
    with open(CSV, "a", newline="") as f:
        w = csv.writer(f)
        for r in uniq:
            if (r["kv"], r["fact"][:60]) in existing:
                continue
            # key_type,key_value,fact_text,namesake,history_blurb,image_url,image_source_url,source_label,source_url,confidence
            w.writerow(["street_name", r["kv"], r["fact"], r["namesake"] or "",
                        r["fact"], "", "", r["label"], r["url"] or "", r["conf"]])
            added += 1

    n = fetch_all("SELECT count(*) AS n FROM fact WHERE key_type='street_name'", {})[0]["n"]
    print(f"Imported {len(uniq)} pilot facts (>= {MIN_CONF} conf), {added} new to CSV. "
          f"Total street facts now: {n}")


if __name__ == "__main__":
    sys.exit(main())
