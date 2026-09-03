# Register an official bike-facility source for a city

Adds (or replaces) a source in the session registry so that
[cl_fetch_official(city)](https://mjorden.github.io/cyclelanes/reference/cl_fetch_official.md)
works for it. Two source types are supported:

## Usage

``` r
cl_register_source(
  city,
  url,
  class_field,
  crosswalk,
  type = c("arcgis", "file"),
  label = city,
  id_field = NULL,
  name_field = NULL,
  extra_fields = NULL,
  existing_where = NULL,
  existing_filter = NULL,
  attribution = NULL,
  homepage = NULL
)
```

## Arguments

- city:

  Short lower-case key, e.g. `"portland"`.

- url:

  Layer endpoint or file location (see Details).

- class_field:

  Name of the attribute holding the facility class.

- crosswalk:

  Named character vector mapping each value of `class_field` to a level
  of
  [`cl_facility_levels()`](https://mjorden.github.io/cyclelanes/reference/cl_facility_levels.md).
  Unmapped values become `none` with a warning at fetch time.

- type:

  `"arcgis"` or `"file"`.

- label:

  Human-readable name.

- id_field, name_field:

  Optional attribute names for a stable feature id and a street/route
  name.

- extra_fields:

  Optional named character vector: output column name = source attribute
  name, copied through verbatim.

- existing_where:

  For `"arcgis"` sources, an SQL where clause that restricts to built
  (not planned) facilities.

- existing_filter:

  A function taking the raw `sf` and returning a logical vector; applied
  after reading for either type.

- attribution, homepage:

  Provenance strings reported by
  [`cl_sources()`](https://mjorden.github.io/cyclelanes/reference/cl_sources.md).

## Value

The registered source definition, invisibly.

## Details

- `"arcgis"`: `url` is an ArcGIS REST **layer** endpoint
  (`.../FeatureServer/<n>` or `.../MapServer/<n>`). Features are paged
  through the `query` operation as GeoJSON. `existing_where` is an SQL
  `where` clause applied server-side.

- `"file"`: `url` is anything
  [`sf::st_read()`](https://r-spatial.github.io/sf/reference/st_read.html)
  can open – a local path or a direct URL to GeoJSON, a zipped
  shapefile, a GeoPackage, and so on.

## Examples

``` r
cl_register_source(
  "exampleville",
  url = "https://example.org/bikeways.geojson",
  type = "file",
  class_field = "FACILITY",
  crosswalk = c("Protected Bike Lane" = "protected_lane",
                "Bike Lane" = "painted_lane",
                "Multi-Use Trail" = "separated_path")
)
cl_sources()
#>           city            label   type
#> 1 exampleville     exampleville   file
#> 2       denver Denver, Colorado arcgis
#>                                            homepage
#> 1                                              <NA>
#> 2 https://opendata-geospatialdenver.hub.arcgis.com/
#>                                                                                                                                attribution
#> 1                                                                                                                                     <NA>
#> 2 City and County of Denver, Denver Moves: Bikes 2025 bikeway inventory (Denver_Bicycle_Facilities_ODC), via the Denver Open Data Catalog.
```
