# Classify OpenStreetMap ways into the facility taxonomy

Normalises the OSM bicycle tagging on each way into the levels of
[`cl_facility_levels()`](https://mjorden.github.io/cyclelanes/reference/cl_facility_levels.md),
resolving the per-side tags so that each street gets a left, a right,
and an overall classification.

## Usage

``` r
cl_classify(x, drop_none = FALSE, keep_tags = FALSE, strict = FALSE)
```

## Arguments

- x:

  An `sf` object from
  [`cl_fetch_osm()`](https://mjorden.github.io/cyclelanes/reference/cl_fetch_osm.md),
  or any `sf` of ways with OSM-style tag columns. Missing tag columns
  are treated as absent tags.

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

## Value

An `sf` with columns `osm_id`, `name`, `highway`, `facility_type`,
`facility_left`, `facility_right` (factors over
[`cl_facility_levels()`](https://mjorden.github.io/cyclelanes/reference/cl_facility_levels.md)),
`n_sides` (0-2, `NA` for separated paths), `contraflow`,
`shared_with_pedestrians`, `oneway`, `surface`, `length_m`, and
geometry.

## Details

The rules, in order:

1.  `highway=cycleway` is a `separated_path` for the whole way, unless
    it is shared with pedestrians (`segregated=no` or
    `foot=designated`), in which case it is a `shared_use_path`.
    `highway=path`, `footway`, `pedestrian`, `track` or `bridleway` with
    `bicycle=designated` is a `shared_use_path`. A sidewalk
    (`footway=sidewalk` or `footway=crossing`) is never a facility,
    whatever its `bicycle` tag. Side columns are `NA` for paths.

2.  Otherwise each side starts from `cycleway=*`, is overridden by
    `cycleway:both=*`, and then by `cycleway:left=*` /
    `cycleway:right=*`.

3.  A `painted_lane` side with a truthy `cycleway[:side]:buffer` tag
    becomes `buffered_lane`.

4.  `bicycle_road=yes` or `cyclestreet=yes` makes any side that has no
    other facility a `neighborhood_bikeway`.

5.  `facility_type` is the more protected of the two sides.

`cycleway=separate` / `sidepath` (the facility is mapped as its own way)
and `cycleway=no` both yield `none`, so nothing is double-counted.

## Examples

``` r
ways <- sf::st_sf(
  highway = c("residential", "cycleway", "primary"),
  cycleway = c("lane", NA, "no"),
  `cycleway:right:buffer` = c("yes", NA, NA),
  geometry = sf::st_sfc(
    sf::st_linestring(rbind(c(-105, 39.7), c(-104.999, 39.7))),
    sf::st_linestring(rbind(c(-105, 39.71), c(-104.999, 39.71))),
    sf::st_linestring(rbind(c(-105, 39.72), c(-104.999, 39.72))),
    crs = 4326
  ),
  check.names = FALSE
)
cl_classify(ways)[, c("facility_type", "facility_left", "facility_right")]
#> Simple feature collection with 3 features and 3 fields
#> Geometry type: LINESTRING
#> Dimension:     XY
#> Bounding box:  xmin: -105 ymin: 39.7 xmax: -104.999 ymax: 39.72
#> Geodetic CRS:  WGS 84
#>    facility_type facility_left facility_right                       geometry
#> 1  buffered_lane  painted_lane  buffered_lane LINESTRING (-105 39.7, -104...
#> 2 separated_path          <NA>           <NA> LINESTRING (-105 39.71, -10...
#> 3           none          none           none LINESTRING (-105 39.72, -10...
```
