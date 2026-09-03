# Administrative boundary polygon for a place

Geocodes `place` through Nominatim with `polygon_geojson=1` and returns
the matching boundary as an `sf` polygon. Used by
[`cl_fetch_osm()`](https://mjorden.github.io/cyclelanes/reference/cl_fetch_osm.md)
and
[`cl_bike_lanes()`](https://mjorden.github.io/cyclelanes/reference/cl_bike_lanes.md)
to clip a bounding-box query to the place itself, so that "Denver,
Colorado" does not include Lakewood and Aurora.

## Usage

``` r
cl_boundary(place)
```

## Arguments

- place:

  A place name, or an `sf`/`sfc` polygon which is returned as-is
  (unioned, in WGS84) so callers can supply their own boundary.

## Value

An `sf` with one row: `name` (Nominatim's display name), `osm_type`,
`osm_id`, and a `POLYGON`/`MULTIPOLYGON` geometry in EPSG:4326.

## Examples

``` r
if (FALSE) { # \dontrun{
den <- cl_boundary("Denver, Colorado")
plot(sf::st_geometry(den))
} # }
```
