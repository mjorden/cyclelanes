# Fetch a city's official bike-facility inventory

Reads the registered source for `city` (see
[`cl_sources()`](https://mjorden.github.io/cyclelanes/reference/cl_sources.md))
and returns it in the same shape and taxonomy as the OpenStreetMap
output, so
[`cl_summary()`](https://mjorden.github.io/cyclelanes/reference/cl_summary.md)
and
[`cl_compare()`](https://mjorden.github.io/cyclelanes/reference/cl_compare.md)
work on either.

## Usage

``` r
cl_fetch_official(
  city = "denver",
  existing_only = TRUE,
  bbox = NULL,
  page_size = 2000
)
```

## Arguments

- city:

  A key from
  [`cl_sources()`](https://mjorden.github.io/cyclelanes/reference/cl_sources.md).
  Default `"denver"`.

- existing_only:

  Restrict to built facilities, dropping planned or recommended ones,
  where the source can distinguish them.

- bbox:

  Optional area to limit the request: WGS84 `c(xmin, ymin, xmax, ymax)`,
  anything
  [`cl_bbox()`](https://mjorden.github.io/cyclelanes/reference/cl_bbox.md)
  accepts, or an `sf`/`sfc` **polygon** such as the output of
  [`cl_boundary()`](https://mjorden.github.io/cyclelanes/reference/cl_boundary.md).
  The bounding box is applied server-side for ArcGIS sources and after
  reading for file sources; a polygon additionally clips the result to
  its outline, so it matches a clipped
  [`cl_bike_lanes()`](https://mjorden.github.io/cyclelanes/reference/cl_bike_lanes.md)
  layer.

- page_size:

  Records per request for ArcGIS sources. Capped at the layer's
  advertised `maxRecordCount` (typically 1000 or 2000); paging continues
  while the server reports `exceededTransferLimit`.

## Value

An `sf` in WGS84 with columns `source_id`, `name`, `official_class` (the
source's own label), `facility_type` (factor over
[`cl_facility_levels()`](https://mjorden.github.io/cyclelanes/reference/cl_facility_levels.md)),
any `extra_fields` from the source definition, `length_m`, and geometry.
`attr(x, "cl_source")` holds the city key and
`attr(x, "cl_attribution")` the provenance string.

## Examples

``` r
if (FALSE) { # \dontrun{
den <- cl_fetch_official("denver")
cl_summary(den)
} # }
```
