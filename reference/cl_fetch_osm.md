# Fetch raw bicycle-related ways from OpenStreetMap

Queries the Overpass API for every way inside `place` that carries a tag
which can denote bicycle infrastructure: `highway=cycleway`, any
`cycleway`, `cycleway:left`, `cycleway:right` or `cycleway:both` tag,
`bicycle=designated`, `bicycle_road=yes`, or `cyclestreet=yes`. The
result is *unclassified*: many of these ways (a footway with
`bicycle=designated`, a road tagged `cycleway=no`) are not facilities.
Pass it to
[`cl_classify()`](https://mjorden.github.io/cyclelanes/reference/cl_classify.md)
or use
[`cl_bike_lanes()`](https://mjorden.github.io/cyclelanes/reference/cl_bike_lanes.md)
which does both.

## Usage

``` r
cl_fetch_osm(
  place,
  timeout = 180,
  clip = TRUE,
  overpass_url = NULL,
  retries = 3,
  tile = NULL,
  cache = FALSE,
  cache_dir = cl_cache_dir(),
  cache_max_age = 30
)
```

## Arguments

- place:

  One of:

  - a place name geocoded through Nominatim, e.g. `"Denver, Colorado"`
    (respect the Nominatim usage policy: at most one request per second,
    no bulk geocoding);

  - a numeric vector `c(xmin, ymin, xmax, ymax)` in WGS84 degrees;

  - an `sf`, `sfc`, or `bbox` object in any CRS;

  - the 2 x 2 matrix returned by
    [`osmdata::getbb()`](https://docs.ropensci.org/osmdata/reference/getbb.html).

- timeout:

  Overpass server timeout in seconds. City-scale queries can take a
  minute or more; the public Overpass instance rejects long-running
  queries, so keep `place` to a metro area or smaller.

- clip:

  Overpass only takes a bounding box, and the box around a city usually
  spills into its neighbours. `TRUE` (the default) clips the result to
  the place's administrative boundary from
  [`cl_boundary()`](https://mjorden.github.io/cyclelanes/reference/cl_boundary.md)
  when `place` is a name; ways crossing the boundary are cut at it. Pass
  an `sf`/`sfc` polygon to clip to your own boundary with any kind of
  `place`, or `FALSE` to keep the whole box. Ignored for bbox and `sf`
  inputs unless a polygon is supplied.

- overpass_url:

  Overpass endpoint for this call only, e.g.
  `"https://overpass.private.coffee/api/interpreter"`. Must end in
  `/interpreter`. The session-wide default set with
  [`osmdata::set_overpass_url()`](https://docs.ropensci.org/osmdata/reference/set_overpass_url.html)
  is restored afterwards.

- retries:

  How many times to retry a transient failure (429, 502, 503, 504,
  timeout) before giving up. Waits start at 30 s and double, with
  jitter, capped at 5 minutes.

- tile:

  Split the bounding box into tiles of at most this many degrees on a
  side and query each, de-duplicating ways by `osm_id`. `NULL` (default)
  sends one query. Use around `0.25` for areas that time out; note each
  tile is a separate request against the server's per-address rate
  limit.

- cache:

  Store the raw Overpass result under `cache_dir` and reuse it for the
  same bounding box within `cache_max_age` days.

- cache_dir:

  Directory for cached results; see
  [`cl_cache_dir()`](https://mjorden.github.io/cyclelanes/reference/cl_cache_dir.md).

- cache_max_age:

  Maximum age in days of a cached result to reuse.

## Value

An `sf` object of `LINESTRING`s in WGS84 (EPSG:4326) with the raw OSM
tag columns present in the area. A zero-row `sf` if nothing matched. The
WGS84 bounding box queried is stored in `attr(x, "cl_bbox")`, the
clipping polygon (if any) in `attr(x, "cl_boundary")`, and the fetch
time in `attr(x, "cl_fetched")` (the original fetch time for a cache
hit).

## Details

Overpass is a shared public service that answers `HTTP 429` when an
address queries too often and `504` when it is overloaded. Those are
retried with exponential backoff (`retries`), a mirror can be used for
one call (`overpass_url`), large areas can be split into tiles (`tile`),
and results can be cached on disk (`cache`) so a re-run of a script does
not hit the server at all.

## Examples

``` r
if (FALSE) { # \dontrun{
raw <- cl_fetch_osm(c(-105.00, 39.74, -104.98, 39.75))
nrow(raw)

# a mirror, with caching so the next run is instant
raw <- cl_fetch_osm("Boulder, Colorado", cache = TRUE,
                    overpass_url = "https://overpass.private.coffee/api/interpreter")
} # }
```
