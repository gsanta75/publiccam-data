#!/usr/bin/env bash
#
# Builds the national surveillance-camera catalog shipped with PublicCam.
#
# Source: OpenStreetMap (man_made=surveillance) restricted to the Italian
# administrative boundary (relation 365331), queried through the public
# QLever SPARQL endpoint — a single query per run, orders of magnitude
# lighter on OSM infrastructure than per-region Overpass calls.
#
# Usage: Scripts/build-camera-catalog.sh [output.json]
#
# The output is the exact file PublicCam reads, both as the snapshot
# published on GitHub Pages and as the seed bundled in the app.
set -euo pipefail

ENDPOINT="https://qlever.dev/api/osm-planet"
OUT="${1:-$(dirname "$0")/docs/it-cameras.json}"
RAW="$(mktemp "${TMPDIR:-/tmp}/publiccam-catalog.XXXXXX")"
trap 'rm -f "$RAW"' EXIT

# Fewer cameras than this means the query returned a partial result: keep
# the previous catalog rather than shipping a truncated one.
MIN_CAMERAS=8000

read -r -d '' QUERY <<'SPARQL' || true
PREFIX osmrel: <https://www.openstreetmap.org/relation/>
PREFIX ogc: <http://www.opengis.net/rdf#>
PREFIX osmkey: <https://www.openstreetmap.org/wiki/Key:>
PREFIX geo: <http://www.opengis.net/ont/geosparql#>
SELECT ?o ?geom ?type ?operator ?zone WHERE {
  osmrel:365331 ogc:sfContains ?o .
  ?o osmkey:man_made "surveillance" .
  ?o geo:hasGeometry/geo:asWKT ?geom .
  OPTIONAL { ?o osmkey:surveillance:type ?type }
  OPTIONAL { ?o osmkey:operator ?operator }
  OPTIONAL { ?o osmkey:surveillance ?zone }
}
SPARQL

echo "Querying $ENDPOINT …"
curl -sSf -m 300 -G "$ENDPOINT" \
  -H "Accept: text/csv" \
  -A "PublicCam-catalog-build/1.0 (https://github.com/gsanta75/publiccam-data)" \
  --data-urlencode "query=$QUERY" \
  -o "$RAW"

OUT="$OUT" MIN_CAMERAS="$MIN_CAMERAS" RAW="$RAW" python3 - <<'PY'
import csv, json, os, re, sys
from datetime import datetime, timezone

raw, out, minimum = os.environ["RAW"], os.environ["OUT"], int(os.environ["MIN_CAMERAS"])
point = re.compile(r"-?\d+(?:\.\d+)?")

def centroid(wkt):
    """Average of a WKT geometry's vertices — exact for POINT, good enough
    for the handful of ways/relations tagged as surveillance."""
    nums = [float(n) for n in point.findall(wkt)]
    if len(nums) < 2 or len(nums) % 2:
        return None
    lons, lats = nums[0::2], nums[1::2]
    return sum(lats) / len(lats), sum(lons) / len(lons)

cameras, skipped = [], 0
with open(raw, newline="") as handle:
    for row in csv.DictReader(handle):
        uri = row.get("o") or ""
        match = re.search(r"/(node|way|relation)/(\d+)$", uri)
        position = centroid(row.get("geom") or "")
        if not match or position is None:
            skipped += 1
            continue
        lat, lon = position
        # Guard against stray geometries outside the country bounding box.
        if not (35.0 <= lat <= 47.5 and 6.0 <= lon <= 19.0):
            skipped += 1
            continue
        kind, osm_id = match.group(1), int(match.group(2))
        camera = {"i": osm_id, "k": kind[0], "y": round(lat, 6), "x": round(lon, 6)}
        for key, column in (("t", "type"), ("o", "operator"), ("z", "zone")):
            value = (row.get(column) or "").strip()
            if value:
                camera[key] = value
        cameras.append(camera)

if len(cameras) < minimum:
    sys.exit(f"Refusing to write {out}: only {len(cameras)} cameras (expected >= {minimum})")

cameras.sort(key=lambda c: (c["k"], c["i"]))
document = {
    "version": 1,
    "generated": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "attribution": "© OpenStreetMap contributors — ODbL",
    "cameras": cameras,
}
os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
with open(out, "w") as handle:
    json.dump(document, handle, ensure_ascii=False, separators=(",", ":"))
    handle.write("\n")

print(f"Wrote {out}: {len(cameras)} cameras ({skipped} skipped), "
      f"{os.path.getsize(out) / 1024:.0f} KB")
PY
