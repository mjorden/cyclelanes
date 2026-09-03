# cyclelanes

Bicycle infrastructure for any place, as a tidy `sf` object.

`cyclelanes` pulls every bicycle-related way for a place from
OpenStreetMap, normalises the dozen-odd OSM tagging conventions into one
facility taxonomy with a per-side classification, and can run a city's
official bike-facility inventory through the same taxonomy so the two can
be summarised and compared. Denver, Colorado is the built-in worked
example; other cities plug in through a source registry.

There is no Google Maps source, and there will not be one: Google exposes
no bike-lane data endpoint and its terms forbid scraping the map layer.
OpenStreetMap is where that data actually lives.

## Install

```r
# install.packages("remotes")
remotes::install_github("mjorden/cyclelanes")
```

`sf` and `osmdata` are the heavy dependencies; both ship CRAN binaries for
Windows and macOS. `ggplot2` is optional, for `cl_plot()`.

## Quick start

```r
library(cyclelanes)

# 1. OpenStreetMap, any place name or bounding box. A place name is
#    clipped to its administrative boundary, so this is Denver proper,
#    not the bounding box that spills into Lakewood and Aurora.
denver <- cl_bike_lanes("Denver, Colorado")
cl_summary(denver)
#>          facility_type n_segments length_km length_mi share
#> 1       separated_path       1843     412.7     256.4 0.41
#> 2       protected_lane        212      48.1      29.9 0.05
#> ...

cl_plot(denver, title = "Denver bike facilities (OpenStreetMap)")

# 2. The city's own inventory, through the same taxonomy, cut to the same
#    boundary so the two layers cover the same ground
official <- cl_fetch_official("denver", bbox = attr(denver, "cl_boundary"))
cl_summary(official, by = c("facility_type", "status"))

# 3. How well do they agree?
cmp <- cl_compare(denver, official, tolerance = 15)
cmp
#> <cl_comparison> tolerance = 15 m
#>    layer n_segments length_km matched_km matched_frac
#>      osm       ...
#> official       ...

# Official facilities that OSM does not know about
missing <- dplyr::filter(cmp$official, matched_frac < 0.5)
cl_plot(missing)
```

A bounding box works anywhere in the world and is the fastest way to
iterate:

```r
lodo <- cl_bike_lanes(c(-105.005, 39.740, -104.985, 39.752))
```

To try the package with no network at all, the same downtown box ships
frozen as `denver_lodo`: raw OSM ways plus the city's segments, fetched
2026-09-03.

```r
lanes <- cl_classify(denver_lodo$osm, drop_none = TRUE)
cl_compare(lanes, denver_lodo$official)
```

## The taxonomy

Every facility from either source lands in one of these levels, ordered
from most to least physically separated from motor traffic:

| level | meaning | typical OSM tagging |
|---|---|---|
| `separated_path` | dedicated off-street cycleway or trail | `highway=cycleway` |
| `shared_use_path` | off-street path shared with pedestrians | `highway=path/footway` + `bicycle=designated`; `highway=cycleway` + `segregated=no` |
| `protected_lane` | on-street, physically separated | `cycleway=track` |
| `buffered_lane` | painted lane with painted buffer | `cycleway=lane` + `cycleway:buffer=*` |
| `painted_lane` | painted lane | `cycleway=lane` |
| `neighborhood_bikeway` | low-traffic street designated for bikes | `bicycle_road=yes`, `cyclestreet=yes` |
| `bus_bike_lane` | shared bus and bike lane | `cycleway=share_busway` |
| `shared_lane` | sharrows | `cycleway=shared_lane` |
| `shoulder` | rideable paved shoulder | `cycleway=shoulder` |
| `none` | no facility | `cycleway=no`, absent, unrecognised |

For OSM, `cl_classify()` resolves `cycleway`, `cycleway:both`,
`cycleway:left` and `cycleway:right` into a `facility_left` and a
`facility_right`, upgrades painted lanes with a buffer tag, flags
contraflow lanes, and reports the more protected side as `facility_type`.
`cycleway=separate` (the lane is mapped as its own way) yields `none` so
nothing is counted twice. Sidewalks (`footway=sidewalk`) are never
facilities, whatever their `bicycle` tag, and `strict = TRUE` additionally
drops shared-use paths with no paved surface tag, which removes most of
the park footways that mappers mark bike-friendly.

## Adding a city

`cl_sources()` lists what is registered. To add one, supply the layer, the
attribute that holds the facility class, and a crosswalk from that
attribute's values into the taxonomy:

```r
cl_register_source(
  "portland",
  type = "arcgis",
  url = "https://.../FeatureServer/0",
  class_field = "Facility",
  crosswalk = c(
    "Protected Bike Lane" = "protected_lane",
    "Buffered Bike Lane"  = "buffered_lane",
    "Bike Lane"           = "painted_lane",
    "Neighborhood Greenway" = "neighborhood_bikeway",
    "Multi-Use Path"      = "separated_path"
  ),
  existing_where = "Status = 'Active'",
  attribution = "City of Portland Open Data"
)
cl_fetch_official("portland")
```

`type = "arcgis"` pages through any ArcGIS REST layer as GeoJSON.
`type = "file"` hands the location to `sf::st_read()`, so a GeoJSON URL, a
zipped shapefile, or a local GeoPackage all work. Class values missing
from the crosswalk are mapped to `none` with a warning naming them, so a
stale crosswalk is loud rather than silent. Pull requests adding cities to
the built-in registry are welcome.

## Caveats

- **OSM completeness varies.** Trails and protected lanes tend to be
  mapped well; neighborhood bikeways and shared streets, which have little
  physical presence, are often missing. `cl_compare()` exists to make
  that visible.
- **The Denver source is the 2025 Denver Moves: Bikes inventory**, which
  carries both existing and future bikeways. `existing_only = TRUE` (the
  default) keeps segments with an existing facility type; the proposed
  type is still available in the `proposed_class` column.
- **Type agreement is length-weighted and spatial.** `cl_compare()`
  assigns each segment the other layer's type that covers most of it
  within the tolerance. Where two facilities run side by side (a trail
  beside a painted lane) the nearer one wins, and adjacent levels such as
  painted vs buffered lane are reported separately because that
  distinction is often a tagging choice.
- **Overpass and Nominatim are shared public services.** A whole metro
  area is fine; a state is not. Respect the Nominatim usage policy for
  geocoding. The public Overpass instance answers `HTTP 429` when one
  address queries too often and `504` when it is busy; `cl_fetch_osm()`
  retries those with backoff, and you can use a mirror for one call and
  cache the result so a re-run never touches the server:

  ```r
  denver <- cl_bike_lanes("Denver, Colorado", cache = TRUE,
                          overpass_url = "https://overpass.private.coffee/api/interpreter")
  ```

  Cached results live in `cl_cache_dir()` for 30 days by default;
  `cl_cache_clear()` empties it.
- **Official data is licensed by each city.** The Denver layer is
  published under the Denver Open Data terms; `cl_sources()` carries the
  attribution string to reproduce.

## Development

```r
devtools::test()      # offline suite
```

The tests that talk to Overpass, Nominatim, and the Denver ArcGIS service
are opt-in so CI never fails on a shared server's rate limit:

```r
withr::with_envvar(c(CYCLELANES_LIVE_TESTS = "true"), devtools::test())
```

## License

MIT. OpenStreetMap data is © OpenStreetMap contributors, ODbL.
