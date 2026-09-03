# Package index

## Fetch from OpenStreetMap

Everything for a place, from Overpass, with retries, mirrors and a
cache.

- [`cl_bike_lanes()`](https://mjorden.github.io/cyclelanes/reference/cl_bike_lanes.md)
  : Bike lanes for a place, fetched from OpenStreetMap and classified
- [`cl_fetch_osm()`](https://mjorden.github.io/cyclelanes/reference/cl_fetch_osm.md)
  : Fetch raw bicycle-related ways from OpenStreetMap
- [`cl_bbox()`](https://mjorden.github.io/cyclelanes/reference/cl_bbox.md)
  : Resolve a place into a WGS84 bounding box
- [`cl_boundary()`](https://mjorden.github.io/cyclelanes/reference/cl_boundary.md)
  : Administrative boundary polygon for a place
- [`cl_cache_dir()`](https://mjorden.github.io/cyclelanes/reference/cl_cache_dir.md)
  [`cl_cache_clear()`](https://mjorden.github.io/cyclelanes/reference/cl_cache_dir.md)
  : Where cached Overpass results live

## Classify

The facility taxonomy and how OSM tags map into it.

- [`cl_classify()`](https://mjorden.github.io/cyclelanes/reference/cl_classify.md)
  : Classify OpenStreetMap ways into the facility taxonomy
- [`cl_facility_levels()`](https://mjorden.github.io/cyclelanes/reference/cl_facility_levels.md)
  : The cyclelanes facility taxonomy

## Official city inventories

A registry of municipal sources read through the same taxonomy.

- [`cl_fetch_official()`](https://mjorden.github.io/cyclelanes/reference/cl_fetch_official.md)
  : Fetch a city's official bike-facility inventory
- [`cl_sources()`](https://mjorden.github.io/cyclelanes/reference/cl_sources.md)
  : Registered official bike-facility data sources
- [`cl_register_source()`](https://mjorden.github.io/cyclelanes/reference/cl_register_source.md)
  : Register an official bike-facility source for a city

## Analyse

- [`cl_summary()`](https://mjorden.github.io/cyclelanes/reference/cl_summary.md)
  : Summarise facility length by type
- [`cl_compare()`](https://mjorden.github.io/cyclelanes/reference/cl_compare.md)
  : Compare OpenStreetMap bike lanes against an official inventory

## Plot

- [`cl_plot()`](https://mjorden.github.io/cyclelanes/reference/cl_plot.md)
  : Quick map of classified bike lanes
- [`cl_palette()`](https://mjorden.github.io/cyclelanes/reference/cl_palette.md)
  : Colours for the facility taxonomy

## Data

- [`denver_lodo`](https://mjorden.github.io/cyclelanes/reference/denver_lodo.md)
  : Downtown Denver bike facilities, frozen
