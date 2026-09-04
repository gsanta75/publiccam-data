# publiccam-data

The national catalog of surveillance cameras used by
[PublicCam](https://github.com/gsanta75/PublicCam), an iOS app that helps
Italian citizens send the urgent CCTV-footage preservation request
(Art. 18 GDPR) to the competent municipality.

This repository holds only data and the script that produces it. It is
public so the extraction is auditable and so the snapshot can be served as
a static file — the app fetches it directly, and never calls an OSM
endpoint at runtime.

## The snapshot

    https://gsanta75.github.io/publiccam-data/it-cameras.json

Every OpenStreetMap object tagged `man_made=surveillance` inside the
Italian administrative boundary: about 14,500 points, ~1 MB of JSON and
~210 KB over the wire once compressed.

```json
{
  "version": 1,
  "generated": "2026-09-04T09:45:16Z",
  "attribution": "© OpenStreetMap contributors — ODbL",
  "cameras": [
    {"i": 195511300, "k": "n", "y": 43.318343, "x": 11.325655, "t": "camera", "z": "public"}
  ]
}
```

| Key | Meaning |
| --- | --- |
| `i` | OSM object id |
| `k` | OSM object kind: `n`ode, `w`ay, `r`elation (ids are only unique within a kind) |
| `y` / `x` | Latitude / longitude, 6 decimals. Ways and relations are reduced to the centroid of their vertices |
| `t` | `surveillance:type`, when tagged |
| `o` | `operator`, when tagged |
| `z` | `surveillance` — the surveilled zone — when tagged |

Cameras are sorted by kind and id, so a rebuild that changes nothing
produces a byte-identical file and no commit.

## How it is built

`build-catalog.sh` runs one SPARQL query against the public
[QLever](https://qlever.cs.uni-freiburg.de/) OSM endpoint and reshapes the
result. One query per week is a negligible load, and vastly lighter than
the per-region Overpass calls the app used to make — those rate-limit and
block per IP, which is what this catalog replaces.

```sh
./build-catalog.sh              # writes docs/it-cameras.json
./build-catalog.sh other.json   # or anywhere else
```

The script refuses to write a file with fewer than 8,000 cameras, so a
partial query result can never be published as a valid snapshot. The app
applies the same floor to anything it downloads.

[`update-catalog.yml`](.github/workflows/update-catalog.yml) runs it every
Monday and commits the result when it changed. GitHub Pages serves `docs/`.

## Licence

The data is derived from OpenStreetMap and is published, like the source,
under the [Open Database License](https://opendatacommons.org/licenses/odbl/):
© OpenStreetMap contributors. Any app or service showing it must carry that
attribution. `build-catalog.sh` is MIT licensed.
