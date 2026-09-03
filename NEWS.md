# cyclelanes 0.5.0

"Safety": reported crashes through the same registry pattern as
facilities, with the denominator problem stated plainly.

* `cl_fetch_crashes()` and a crash source registry
  (`cl_register_crash_source()`, `cl_crash_sources()`) return crashes as
  points with standard columns: date, a severity factor, who was involved
  and -- separately -- who was hurt, intersection versus mid-block, light
  and road condition. Denver Police's traffic-accidents layer (2013 to
  present) is built in (#18, #19).
* `cl_crash_join()` snaps each crash to the nearest facility within a
  tolerance; `cl_crash_rates()` reports reported crashes and serious or
  fatal crashes per **kilometre-year** by facility type, intersection and
  mid-block on separate rows, honouring `install_year` and, with an
  `exposure` column, per million bicycle-kilometres. `cl_plot(crashes = )`
  overlays crashes sized by severity (#20).
* `cl_fetch_fars()` reads NHTSA's FARS national releases (every US fatal
  crash with coordinates since 2001, cached once per year) into the same
  shape, and `cl_fetch_crashes()` falls back to it for a place with no
  registered source (#21).
* `denver_lodo` carries the downtown bicycle crashes for 2019-2025, and
  the Denver vignette gains a safety section with the caveats before the
  numbers (#22).
* `cl_summary()` on a point layer reports counts and shares instead of
  lengths.

# cyclelanes 0.4.0

"Richer classification and analysis": beyond the presence of a facility.

## Classification

* Lane-quality attributes from the side that carries the facility:
  `lane_kind` (exclusive / advisory / pictogram), `separation`, `two_way`,
  `contraflow_allowed`, `width_m` (parsed from metres, centimetres, feet
  or inches), the parent road's `road_maxspeed_kph` and `road_lanes`, and
  `lit`, `surface`, `smoothness` (#11).
* `cl_lts()`: Level of Traffic Stress 1-4 following Mekuria, Furth and
  Nixon (2012) as simplified in Furth's 2017 tables, on segments. Missing
  speed or lanes are filled from the road class and `lts_basis` says so.
  The rule table ships in `inst/extdata/lts_rules.csv` (#12).

## Analysis

* `cl_fetch_osm(date = )` and `cl_bike_lanes(date = )` fetch the network
  as it was on a date through Overpass's attic data; `cl_timeline()`
  stacks summaries over a series of dates (#13).
* `cl_as_sfnetwork()` builds a snapped, undirected `sfnetworks` graph;
  `cl_components()` labels the connected components of the network at or
  below a stress level, largest first, with a component table (#14).

## Plots and maps

* `cl_plot()` colours by `"lts"` or `"component"`; legend keys are always
  drawn as lines.
* `cl_map()`: an interactive `leaflet` map of any layer, or of a
  comparison with toggleable OSM / official groups and the gaps
  highlighted; popups escape every string and link each way to
  openstreetmap.org (#16).

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
