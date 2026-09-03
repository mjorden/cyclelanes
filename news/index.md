# Changelog

## cyclelanes 0.2.0

“Trustworthy numbers”: everything the first city-wide Denver run
exposed.

### Fetching

- [`cl_fetch_osm()`](https://mjorden.github.io/cyclelanes/reference/cl_fetch_osm.md)
  and
  [`cl_bike_lanes()`](https://mjorden.github.io/cyclelanes/reference/cl_bike_lanes.md)
  clip a place-name query to the place’s administrative boundary
  (`clip = TRUE`, via the new
  [`cl_boundary()`](https://mjorden.github.io/cyclelanes/reference/cl_boundary.md)),
  so “Denver, Colorado” no longer includes Lakewood and Aurora.
  `cl_fetch_official(bbox = )` accepts the same polygon
  ([\#2](https://github.com/mjorden/cyclelanes/issues/2)).
- Overpass resilience: transient failures (429/502/503/504/timeouts) are
  retried with exponential backoff; `overpass_url` uses a mirror for one
  call; `tile` splits large boxes; `cache = TRUE` stores results under
  [`cl_cache_dir()`](https://mjorden.github.io/cyclelanes/reference/cl_cache_dir.md)
  and reuses them for `cache_max_age` days
  ([\#6](https://github.com/mjorden/cyclelanes/issues/6)).
- Geocoding calls Nominatim directly with base tools instead of through
  [`osmdata::getbb()`](https://docs.ropensci.org/osmdata/reference/getbb.html),
  so it works on R installs whose `curl` package is too old for `httr2`.
- The ArcGIS reader honours the server’s `maxRecordCount` and
  `exceededTransferLimit`; a server capping below `page_size` no longer
  silently truncates the layer
  ([\#1](https://github.com/mjorden/cyclelanes/issues/1)).

### Classification

- New `shared_use_path` level between `separated_path` and
  `protected_lane` for paths shared with pedestrians. Sidewalks
  (`footway=sidewalk`) are never facilities.
  `cl_classify(strict = TRUE)` drops shared paths with no paved surface
  tag ([\#3](https://github.com/mjorden/cyclelanes/issues/3)).
- A `highway=cycleway` that is really an on-street lane drawn as its own
  way – `is_sidepath=yes`, a `track` tag, or (`sidepath_by_name = TRUE`)
  a street-like name – is a `protected_lane` with
  `mapped_separately = TRUE`
  ([\#30](https://github.com/mjorden/cyclelanes/issues/30)).

### Comparison

- [`cl_compare()`](https://mjorden.github.io/cyclelanes/reference/cl_compare.md)
  reports facility-type agreement: `other_type`, `type_match`,
  `type_adjacent` per segment; `type_agreement` and `type_adjacent` in
  the summaries; and a `confusion` matrix of official type by OSM type
  in kilometres. `cl_plot(colour = "type_match")` maps it
  ([\#4](https://github.com/mjorden/cyclelanes/issues/4)).

### Data, docs, tests

- `denver_lodo`: a frozen downtown Denver sample of both sources so
  examples, tests and the vignette run offline; snapshot tests guard the
  classification rules
  ([\#5](https://github.com/mjorden/cyclelanes/issues/5)).
- pkgdown site at <https://mjorden.github.io/cyclelanes/> with a Denver
  vignette ([\#15](https://github.com/mjorden/cyclelanes/issues/15)).
- Live network tests are opt-in through `CYCLELANES_LIVE_TESTS=true`.

## cyclelanes 0.1.0

- Initial release: OpenStreetMap fetch via Overpass, the nine-level
  facility taxonomy with per-side classification, a registry of official
  city sources with Denver built in,
  [`cl_summary()`](https://mjorden.github.io/cyclelanes/reference/cl_summary.md),
  [`cl_compare()`](https://mjorden.github.io/cyclelanes/reference/cl_compare.md),
  [`cl_plot()`](https://mjorden.github.io/cyclelanes/reference/cl_plot.md).
