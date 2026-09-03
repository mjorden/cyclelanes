# cyclelanes 0.3.0

"More cities": adding a city is a fifteen-minute job, and a whole city no
longer depends on Overpass.

## Sources

* Austin, Boulder and Seattle join Denver as built-in official sources
  (#9). Boulder is a MapServer capped at 1000 rows per page in state-plane
  feet; the reader handles it.
* `cl_inspect_source()` prints a candidate layer's fields, the distinct
  values of its text fields, and where its extent sits, so the class field
  can be found and a wrong-city layer spotted before any crosswalk is
  written (#7).
* `cl_check_source()` compares a crosswalk with the live class values and
  reports mapped, unmapped and stale entries; `cl_fetch_official()`'s
  unmapped warning now says how many segments and kilometres are affected;
  a weekly `check-sources` workflow opens an issue on drift (#8).
* The ArcGIS reader falls back to Esri JSON for servers without GeoJSON
  output, accepts MapServer layers, and transforms answers that ignore
  `outSR` or arrive as CRS-less state-plane GeoJSON (#10).

## Fetching

* `cl_fetch_osm(backend = "extract")` reads the smallest Geofabrik extract
  covering the area through `osmextract` instead of querying Overpass:
  no rate limit, and every later place in the same region is local
  (#32). The extract is matched on the clip boundary polygon, its size is
  reported and capped by `max_extract_mb`, downloads persist under
  `cl_cache_dir()/extracts`, and the download timeout is raised (#39).
  Tag names GDAL writes with underscores (`cycleway_right`) are mapped
  back to their OSM form (#42).
* `.clip_lines()` no longer errors when a way only touches the boundary
  at a point.

## Docs

* README and the Denver vignette carry the real city-wide numbers and
  four figures from a run through the Colorado extract, clipped to the
  city boundary.

# cyclelanes 0.2.0

"Trustworthy numbers": everything the first city-wide Denver run exposed.

## Fetching

* `cl_fetch_osm()` and `cl_bike_lanes()` clip a place-name query to the
  place's administrative boundary (`clip = TRUE`, via the new
  `cl_boundary()`), so "Denver, Colorado" no longer includes Lakewood and
  Aurora. `cl_fetch_official(bbox = )` accepts the same polygon (#2).
* Overpass resilience: transient failures (429/502/503/504/timeouts) are
  retried with exponential backoff; `overpass_url` uses a mirror for one
  call; `tile` splits large boxes; `cache = TRUE` stores results under
  `cl_cache_dir()` and reuses them for `cache_max_age` days (#6).
* Geocoding calls Nominatim directly with base tools instead of through
  `osmdata::getbb()`, so it works on R installs whose `curl` package is
  too old for `httr2`.
* The ArcGIS reader honours the server's `maxRecordCount` and
  `exceededTransferLimit`; a server capping below `page_size` no longer
  silently truncates the layer (#1).

## Classification

* New `shared_use_path` level between `separated_path` and
  `protected_lane` for paths shared with pedestrians. Sidewalks
  (`footway=sidewalk`) are never facilities. `cl_classify(strict = TRUE)`
  drops shared paths with no paved surface tag (#3).
* A `highway=cycleway` that is really an on-street lane drawn as its own
  way -- `is_sidepath=yes`, a `track` tag, or (`sidepath_by_name = TRUE`)
  a street-like name -- is a `protected_lane` with `mapped_separately =
  TRUE` (#30).

## Comparison

* `cl_compare()` reports facility-type agreement: `other_type`,
  `type_match`, `type_adjacent` per segment; `type_agreement` and
  `type_adjacent` in the summaries; and a `confusion` matrix of official
  type by OSM type in kilometres. `cl_plot(colour = "type_match")` maps it
  (#4).

## Data, docs, tests

* `denver_lodo`: a frozen downtown Denver sample of both sources so
  examples, tests and the vignette run offline; snapshot tests guard the
  classification rules (#5).
* pkgdown site at <https://mjorden.github.io/cyclelanes/> with a Denver
  vignette (#15).
* Live network tests are opt-in through `CYCLELANES_LIVE_TESTS=true`.

# cyclelanes 0.1.0

* Initial release: OpenStreetMap fetch via Overpass, the nine-level
  facility taxonomy with per-side classification, a registry of official
  city sources with Denver built in, `cl_summary()`, `cl_compare()`,
  `cl_plot()`.
