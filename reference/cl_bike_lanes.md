# Bike lanes for a place, fetched from OpenStreetMap and classified

Convenience wrapper:
[`cl_fetch_osm()`](https://mjorden.github.io/cyclelanes/reference/cl_fetch_osm.md)
followed by
[`cl_classify()`](https://mjorden.github.io/cyclelanes/reference/cl_classify.md),
with non-facility ways dropped by default.

## Usage

``` r
cl_bike_lanes(
  place,
  drop_none = TRUE,
  keep_tags = FALSE,
  strict = FALSE,
  timeout = 180,
  clip = TRUE,
  ...
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

- drop_none:

  Drop ways whose overall `facility_type` is `none`.

- keep_tags:

  Keep every input column in addition to the standard output columns. By
  default only `osm_id`, `name`, `highway`, `oneway` and `surface`
  survive from the input.

- strict:

  Also drop `shared_use_path` ways that are not `highway=cycleway` and
  lack a paved `surface` tag (`paved`, `asphalt`, `concrete`,
  `paving_stones`, ...). Park footways that a mapper tagged
  bike-friendly are the bulk of what this removes; use it when you want
  on-road-quality kilometres only.

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

- ...:

  Passed to
  [`cl_fetch_osm()`](https://mjorden.github.io/cyclelanes/reference/cl_fetch_osm.md):
  `overpass_url`, `retries`, `tile`, `cache`, `cache_dir`,
  `cache_max_age`.

## Value

The classified `sf` described in
[`cl_classify()`](https://mjorden.github.io/cyclelanes/reference/cl_classify.md),
with the queried bounding box in `attr(x, "cl_bbox")`, the fetch time in
`attr(x, "cl_fetched")`, and `attr(x, "cl_source") == "openstreetmap"`.

## Examples

``` r
if (FALSE) { # \dontrun{
denver <- cl_bike_lanes("Denver, Colorado")
cl_summary(denver)
cl_plot(denver)
} # }
```
