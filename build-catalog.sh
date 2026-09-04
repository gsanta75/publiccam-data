#!/usr/bin/env bash
#
# Builds the national surveillance-camera catalog served to PublicCam.
#
# Source: the Geofabrik extract of Italy, filtered to OpenStreetMap objects
# tagged man_made=surveillance. Geofabrik is the canonical bulk-download
# mirror for OSM and is meant to be fetched by automated jobs — unlike the
# public query APIs, which rate-limit, block datacenter IPs, or both.
#
# Requires osmium-tool: `apt install osmium-tool` / `brew install osmium-tool`.
#
# Usage: ./build-catalog.sh [output.json]
set -euo pipefail

EXTRACT_URL="https://download.geofabrik.de/europe/italy-latest.osm.pbf"
OUT="${1:-$(dirname "$0")/docs/it-cameras.json}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/publiccam-catalog.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# Fewer cameras than this means something truncated the pipeline: keep the
# previous catalog rather than publishing a partial one.
MIN_CAMERAS=8000

if ! command -v osmium >/dev/null 2>&1; then
  echo "osmium-tool is required (apt install osmium-tool / brew install osmium-tool)" >&2
  exit 1
fi

echo "Downloading $EXTRACT_URL …"
curl -sSfL -m 3600 \
  -A "PublicCam-catalog-build/1.0 (https://github.com/gsanta75/publiccam-data)" \
  -o "$WORK/italy.osm.pbf" "$EXTRACT_URL"

echo "Filtering man_made=surveillance …"
osmium tags-filter "$WORK/italy.osm.pbf" nwr/man_made=surveillance -o "$WORK/cameras.osm.pbf"

# Referenced nodes come along so way and relation geometries can be built;
# the reshaping step below keeps only the objects actually tagged.
echo "Exporting geometries …"
osmium export "$WORK/cameras.osm.pbf" \
  --format geojsonseq --add-unique-id=type_id \
  -o "$WORK/cameras.geojsonseq"

OUT="$OUT" MIN_CAMERAS="$MIN_CAMERAS" WORK="$WORK" python3 - <<'PY'
import json, os, sys
from datetime import datetime, timezone

work, out, minimum = os.environ["WORK"], os.environ["OUT"], int(os.environ["MIN_CAMERAS"])

def centroid(geometry):
    """Average of a geometry's vertices — exact for Point, good enough for
    the handful of ways and relations tagged as surveillance."""
    points = []
    def walk(node):
        if (isinstance(node, list) and len(node) == 2
                and all(isinstance(value, (int, float)) for value in node)):
            points.append(node)
        elif isinstance(node, list):
            for child in node:
                walk(child)
    walk(geometry.get("coordinates", []))
    if not points:
        return None
    return (sum(p[1] for p in points) / len(points),
            sum(p[0] for p in points) / len(points))

cameras, skipped = [], 0
with open(os.path.join(work, "cameras.geojsonseq")) as handle:
    for line in handle:
        line = line.strip().lstrip("\x1e")
        if not line:
            continue
        feature = json.loads(line)
        tags = feature.get("properties") or {}
        # tags-filter keeps referenced members; only the tagged objects count.
        if tags.get("man_made") != "surveillance":
            continue
        identifier = str(tags.get("@id") or feature.get("id") or "")
        position = centroid(feature.get("geometry") or {})
        if not identifier or position is None:
            skipped += 1
            continue
        kind, digits = identifier[0], identifier[1:].lstrip("/")
        if kind not in "nwr" or not digits.isdigit():
            skipped += 1
            continue
        latitude, longitude = position
        camera = {"i": int(digits), "k": kind,
                  "y": round(latitude, 6), "x": round(longitude, 6)}
        for key, tag in (("t", "surveillance:type"), ("o", "operator"), ("z", "surveillance")):
            value = (tags.get(tag) or "").strip()
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
