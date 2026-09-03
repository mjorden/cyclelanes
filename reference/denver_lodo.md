# Downtown Denver bike facilities, frozen

A small, fixed sample of both data sources for a box over downtown
Denver (Cherry Creek trail, the 15th and 16th Street lanes, Union
Station), so examples, tests and vignettes run without touching Overpass
or the city's ArcGIS service. Regenerate with `data-raw/denver_lodo.R`.

## Usage

``` r
denver_lodo
```

## Format

A list with four elements:

- `osm`:

  An `sf` of raw OpenStreetMap ways as returned by
  [`cl_fetch_osm()`](https://mjorden.github.io/cyclelanes/reference/cl_fetch_osm.md),
  cut at the box edge: one row per way with the OSM tag columns present
  in the area (tags that are `NA` for every way are dropped).
  Unclassified; pass it to
  [`cl_classify()`](https://mjorden.github.io/cyclelanes/reference/cl_classify.md).

- `official`:

  An `sf` from
  [cl_fetch_official("denver")](https://mjorden.github.io/cyclelanes/reference/cl_fetch_official.md)
  cut to the same box, already in the package taxonomy.

- `bbox`:

  The WGS84 bounding box, `c(xmin, ymin, xmax, ymax)`.

- `fetched`:

  The `Date` both layers were fetched.

## Source

OpenStreetMap contributors (ODbL) via the Overpass API; City and County
of Denver, Denver Moves: Bikes 2025 bikeway inventory via the Denver
Open Data Catalog.

## Examples

``` r
lanes <- cl_classify(denver_lodo$osm, drop_none = TRUE)
cl_summary(lanes)
#>     facility_type n_segments length_km length_mi      share
#> 1  separated_path         90  5.457209 3.3909516 0.19817790
#> 2 shared_use_path         53  2.292066 1.4242231 0.08323609
#> 3  protected_lane        162 12.726186 7.9076827 0.46214990
#> 4   buffered_lane         18  1.690104 1.0501815 0.06137591
#> 5    painted_lane         66  4.070209 2.5291097 0.14780915
#> 6     shared_lane         24  1.301149 0.8084959 0.04725105
cl_compare(lanes, denver_lodo$official)
#> <cl_comparison> tolerance = 15 m
#> 
#>     layer n_segments length_km matched_km matched_frac type_agreement
#>       osm        413      27.5       25.0        0.908          0.733
#>  official         55      17.9       16.6        0.927          0.780
#>  type_adjacent
#>          0.785
#>          0.836
#> 
#> By facility type:
#>     layer   facility_type n_segments length_km matched_frac type_agreement
#>       osm  separated_path         90       5.5        0.985          0.286
#>       osm shared_use_path         53       2.3        0.506          0.458
#>       osm  protected_lane        162      12.7        0.999          0.993
#>       osm   buffered_lane         18       1.7        0.976          0.676
#>       osm    painted_lane         66       4.1        0.861          0.722
#>       osm     shared_lane         24       1.3        0.473          0.000
#>  official  separated_path          7       1.8        0.998          0.896
#>  official shared_use_path          8       1.1        0.665          0.884
#>  official  protected_lane         22      11.0        0.919          0.711
#>  official   buffered_lane          4       1.0        1.000          1.000
#>  official    painted_lane         14       3.0        0.987          0.845
#>  type_adjacent
#>          0.296
#>          1.000
#>          0.999
#>          1.000
#>          0.727
#>          0.000
#>          1.000
#>          1.000
#>          0.733
#>          1.000
#>          0.995
#> 
#> Official type (rows) vs OSM type (columns), km:
#>                  osm
#> official          separated_path shared_use_path protected_lane buffered_lane
#>   separated_path             1.6             0.2            0.0           0.0
#>   shared_use_path            0.2             0.7            0.0           0.0
#>   protected_lane             3.0             0.2            7.8           0.0
#>   buffered_lane              0.0             0.0            0.0           1.0
#>   painted_lane               0.0             0.0            0.0           0.4
#>                  osm
#> official          painted_lane unmatched
#>   separated_path           0.0       0.0
#>   shared_use_path          0.0       0.2
#>   protected_lane           0.0       0.0
#>   buffered_lane            0.0       0.0
#>   painted_lane             2.5       0.0
```
