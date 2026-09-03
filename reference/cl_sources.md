# Registered official bike-facility data sources

Registered official bike-facility data sources

## Usage

``` r
cl_sources()
```

## Value

A data frame with one row per city: `city` (the key to pass to
[`cl_fetch_official()`](https://mjorden.github.io/cyclelanes/reference/cl_fetch_official.md)),
`label`, `type`, `homepage`, `attribution`.

## Examples

``` r
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
