# cyclelanes: bicycle infrastructure from OpenStreetMap and city open data

Fetch every bicycle-related way for a place from OpenStreetMap,
normalise the tagging into one facility taxonomy (see
[`cl_facility_levels()`](https://mjorden.github.io/cyclelanes/reference/cl_facility_levels.md)),
and optionally pull a city's official bike-facility inventory through
the same taxonomy so the two can be summarised and compared.

## Details

The main entry points are:

- [`cl_bike_lanes()`](https://mjorden.github.io/cyclelanes/reference/cl_bike_lanes.md)
  – fetch + classify OSM for a place name or bounding box

- [`cl_fetch_official()`](https://mjorden.github.io/cyclelanes/reference/cl_fetch_official.md)
  – a city's official inventory, via
  [`cl_sources()`](https://mjorden.github.io/cyclelanes/reference/cl_sources.md)

- [`cl_summary()`](https://mjorden.github.io/cyclelanes/reference/cl_summary.md)
  – length by facility type

- [`cl_compare()`](https://mjorden.github.io/cyclelanes/reference/cl_compare.md)
  – how well the two layers agree

- [`cl_plot()`](https://mjorden.github.io/cyclelanes/reference/cl_plot.md)
  – a quick map

## See also

Useful links:

- <https://mjorden.github.io/cyclelanes/>

- <https://github.com/mjorden/cyclelanes>

- Report bugs at <https://github.com/mjorden/cyclelanes/issues>

## Author

**Maintainer**: Matthew Jorden <matthew.jorden@gmail.com>
