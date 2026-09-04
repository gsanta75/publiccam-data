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

Every OpenStreetMap object tagged `man_made=surveillance` in Italy: about
14,600 points, ~1 MB of JSON and ~215 KB over the wire once compressed.

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

`build-catalog.sh` downloads the [Geofabrik](https://download.geofabrik.de/europe/italy.html)
extract of Italy (~2.2 GB), filters it to `man_made=surveillance` with
[osmium](https://osmcode.org/osmium-tool/) and reshapes the result. It
needs `osmium-tool` — `apt install osmium-tool`, `brew install osmium-tool`
— and takes about four minutes end to end, most of it the download.

```sh
./build-catalog.sh              # writes docs/it-cameras.json
./build-catalog.sh other.json   # or anywhere else
```

Bulk extracts are the channel OSM publishes for automated consumers, which
is why the pipeline uses them rather than a query API. The query APIs are
built for interactive use and defend themselves accordingly: Overpass
rate-limits and blocks per IP — the very problem this catalog removes from
the app — and QLever, fast and convenient from a workstation, answers 403
to datacenter addresses, so it cannot carry an unattended job.

Objects whose geometry osmium cannot build are dropped and counted in the
run output; that is a handful of relations out of ~14,600. The script also
refuses to write a file with fewer than 8,000 cameras, so a truncated run
can never be published as a valid snapshot. The app applies the same floor
to anything it downloads.

[`update-catalog.yml`](.github/workflows/update-catalog.yml) runs it every
Monday and commits the result when it changed. GitHub Pages serves `docs/`,
and its own deployment workflow republishes on that commit — which is how
an update reaches installed apps.

## Licence

The data is derived from OpenStreetMap and is published, like the source,
under the [Open Database License](https://opendatacommons.org/licenses/odbl/):
© OpenStreetMap contributors. Any app or service showing it must carry that
attribution. `build-catalog.sh` is MIT licensed.
