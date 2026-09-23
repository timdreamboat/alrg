#!/usr/bin/env python3
"""
Discover real restaurant candidates near a city from Overture Maps'
open Places dataset (free, no key, CDLA Permissive 2.0 license) --
used as a discovery LEAD source only. Output rows are NOT restaurant
data to store as-is; the pipeline still independently re-verifies
name/address/phone/website from each candidate's own site before
storing anything, and still runs the full menu/allergen pipeline per
restaurant. See pipeline/COVERAGE_PLAN.md for why.

Usage:
    python3 discover_places.py "Cheyenne, WY" [radius_miles] [min_confidence]

Prints one JSON object per line (JSONL) to stdout: overture_id, name,
category, address, city, region, zip, lat, lng, phone, website,
confidence. Caller is responsible for deduping against the
`restaurants` table before treating any row as a new candidate.
"""
import sys
import json
import urllib.request
import urllib.parse

OVERTURE_RELEASE = "2026-08-19.0"  # bump periodically; check docs.overturemaps.org for the current release
RESTAURANT_CATEGORY_PATTERNS = [
    "%restaurant%", "%cafe%", "%diner%", "%pizzeria%",
    "%bar_and_grill%", "%bakery%", "%steakhouse%", "%bistro%",
]


def geocode(query):
    url = "https://nominatim.openstreetmap.org/search?" + urllib.parse.urlencode(
        {"q": query, "format": "json", "limit": 1, "countrycodes": "us"}
    )
    req = urllib.request.Request(url, headers={"User-Agent": "ALRG-discovery/1.0"})
    with urllib.request.urlopen(req, timeout=15) as r:
        data = json.load(r)
    if not data:
        raise SystemExit(f"geocode failed for: {query}")
    return float(data[0]["lat"]), float(data[0]["lon"])


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    place = sys.argv[1]
    radius_miles = float(sys.argv[2]) if len(sys.argv) > 2 else 15.0
    min_confidence = float(sys.argv[3]) if len(sys.argv) > 3 else 0.6

    lat, lng = geocode(place)
    # ~1 degree lat = 69 miles; longitude degree shrinks with latitude, pad generously
    dlat = radius_miles / 69.0
    dlng = radius_miles / (69.0 * max(0.2, abs(__import__("math").cos(__import__("math").radians(lat)))))

    import duckdb
    con = duckdb.connect()
    con.execute("LOAD httpfs; LOAD spatial;")
    con.execute("SET s3_region='us-west-2';")

    cat_clause = " OR ".join(["categories.primary ILIKE ?"] * len(RESTAURANT_CATEGORY_PATTERNS))
    query = f"""
        SELECT id, names.primary as name, categories.primary as category,
               addresses[1].freeform as address, addresses[1].locality as city,
               addresses[1].region as region, addresses[1].postcode as zip,
               bbox.ymin as lat, bbox.xmin as lng,
               phones[1] as phone, websites[1] as website, confidence
        FROM read_parquet(
            's3://overturemaps-us-west-2/release/{OVERTURE_RELEASE}/theme=places/type=place/*',
            filename=true, hive_partitioning=1)
        WHERE ({cat_clause})
          AND confidence >= ?
          AND bbox.xmin BETWEEN ? AND ?
          AND bbox.ymin BETWEEN ? AND ?
    """
    params = RESTAURANT_CATEGORY_PATTERNS + [
        min_confidence, lng - dlng, lng + dlng, lat - dlat, lat + dlat
    ]
    rows = con.execute(query, params).fetchall()
    cols = ["overture_id", "name", "category", "address", "city", "region",
            "zip", "lat", "lng", "phone", "website", "confidence"]
    try:
        for row in rows:
            print(json.dumps(dict(zip(cols, row))))
        print(f"# {len(rows)} candidates near {place} (r={radius_miles}mi, min_confidence={min_confidence})",
              file=sys.stderr)
    except BrokenPipeError:
        pass  # downstream consumer (e.g. `head`) closed early; not an error


if __name__ == "__main__":
    main()
