# Denver: OpenStreetMap against the city's own inventory

This walk-through uses `denver_lodo`, a frozen sample of both data
sources for a small box over downtown Denver, so it runs without network
access. The last section shows the same calls at city scale.

``` r

library(cyclelanes)
```

## 1. Classify the OpenStreetMap ways

`denver_lodo$osm` is exactly what
[`cl_fetch_osm()`](https://mjorden.github.io/cyclelanes/reference/cl_fetch_osm.md)
returns: one row per way with whatever OSM tags exist in the area,
unclassified.

``` r

nrow(denver_lodo$osm)
#> [1] 473
head(names(denver_lodo$osm), 20)
#>  [1] "osm_id"                "name"                  "bicycle"              
#>  [4] "bridge"                "bus"                   "bus:lanes"            
#>  [7] "bus:lanes:forward"     "busway:right"          "change:lanes"         
#> [10] "covered"               "crossing"              "crossing:island"      
#> [13] "crossing:markings"     "crossing:signals"      "cycleway"             
#> [16] "cycleway:both"         "cycleway:both:buffer"  "cycleway:left"        
#> [19] "cycleway:right"        "cycleway:right:buffer"
```

[`cl_classify()`](https://mjorden.github.io/cyclelanes/reference/cl_classify.md)
turns the tagging into the package taxonomy, resolving `cycleway:left` /
`cycleway:right` per side and keeping the more protected side as
`facility_type`. Ways that carry a bicycle tag but are not a facility (a
sidewalk with `bicycle=designated`, a road with `cycleway=no`) are
dropped with `drop_none = TRUE`.

``` r

lanes <- cl_classify(denver_lodo$osm, drop_none = TRUE)
knitr::kable(cl_summary(lanes), digits = 2)
```

| facility_type   | n_segments | length_km | length_mi | share |
|:----------------|-----------:|----------:|----------:|------:|
| separated_path  |         90 |      5.46 |      3.39 |  0.20 |
| shared_use_path |         53 |      2.29 |      1.42 |  0.08 |
| protected_lane  |        162 |     12.73 |      7.91 |  0.46 |
| buffered_lane   |         18 |      1.69 |      1.05 |  0.06 |
| painted_lane    |         66 |      4.07 |      2.53 |  0.15 |
| shared_lane     |         24 |      1.30 |      0.81 |  0.05 |

``` r

cl_plot(lanes, title = "Downtown Denver, OpenStreetMap")
```

![Map of downtown Denver bike facilities from OpenStreetMap, coloured by
facility type](denver_files/figure-html/unnamed-chunk-4-1.png)

## 2. The city’s inventory through the same taxonomy

`denver_lodo$official` is the same box from Denver’s *Denver Moves:
Bikes* 2025 layer, already crosswalked into the taxonomy. The city’s own
class is kept in `official_class`, and `status` says whether a segment
is built as recorded or has upgrades planned.

``` r

knitr::kable(cl_summary(denver_lodo$official, by = c("facility_type", "status")), digits = 2)
```

| facility_type | status | n_segments | length_km | length_mi | share |
|:---|:---|---:|---:|---:|---:|
| separated_path | Existing Bikeway | 7 | 1.79 | 1.11 | 0.10 |
| shared_use_path | Existing Bikeway | 8 | 1.11 | 0.69 | 0.06 |
| protected_lane | Existing Bikeway | 5 | 3.17 | 1.97 | 0.18 |
| protected_lane | Existing Bikeway with Facility Type Changes | 1 | 0.01 | 0.01 | 0.00 |
| protected_lane | Existing Bikeway with Future Upgrades | 15 | 7.55 | 4.69 | 0.42 |
| protected_lane | Future Bikeway | 1 | 0.29 | 0.18 | 0.02 |
| buffered_lane | Existing Bikeway with Facility Type Changes | 4 | 0.97 | 0.60 | 0.05 |
| painted_lane | Existing Bikeway | 1 | 0.13 | 0.08 | 0.01 |
| painted_lane | Existing Bikeway with Facility Type Changes | 13 | 2.84 | 1.77 | 0.16 |

## 3. How well do they agree?

[`cl_compare()`](https://mjorden.github.io/cyclelanes/reference/cl_compare.md)
measures two things. Spatially: what share of each layer lies within
`tolerance` metres of the other. And by type: for every matched segment,
which facility type the other layer assigns to it.

``` r

cmp <- cl_compare(lanes, denver_lodo$official, tolerance = 15)
cmp
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

The confusion matrix is where the story is. Rows are the city’s type,
columns are what OSM calls the same ground, in kilometres.

``` r

round(cmp$confusion, 1)
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

Downtown, both sources agree almost everywhere that *something* exists,
and on *what* for roughly three quarters of the length. Most of the
remaining disagreement is buffered versus painted lanes, which is often
a tagging choice rather than a difference on the ground; `type_adjacent`
counts those as near-misses.

One convention mattered a lot here. Denver’s mappers draw the downtown
protected lanes as their own `highway=cycleway` ways beside the road,
named after the street (“14th Street”, “Lawrence Street”), rather than
as a `cycleway=track` tag on the road. Read literally those are
off-street trails, and before the classifier learned to recognise
street-named cycleways as sidepaths, OSM showed 7 km of protected lane
downtown against the city’s 11 km and type agreement was near 50%. The
rule is `sidepath_by_name`, on by default and documented in
[`?cl_classify`](https://mjorden.github.io/cyclelanes/reference/cl_classify.md).

``` r

cl_plot(cmp$official, colour = "type_match",
        title = "City segments: does OSM agree on the facility type?")
```

![Map of the city's downtown segments coloured green where OpenStreetMap
assigns the same facility type, red where it differs, grey where OSM has
nothing nearby](denver_files/figure-html/unnamed-chunk-8-1.png)

Segments the city has and OSM lacks entirely are the ones with a low
matched fraction:

``` r

gaps <- cmp$official[cmp$official$matched_frac < 0.5, ]
nrow(gaps)
#> [1] 6
knitr::kable(sf::st_drop_geometry(gaps)[, c("name", "official_class", "status")])
```

|  | name | official_class | status |
|:---|:---|:---|:---|
| 5 | Larimer Square | Car-Free Street | Existing Bikeway |
| 34 | Larimer St | Protected Bike Lane | Future Bikeway |
| 38 | Larimer St | Protected Bike Lane | Existing Bikeway with Future Upgrades |
| 41 | Market St | Protected Bike Lane | Existing Bikeway with Future Upgrades |
| 46 | N Mariposa St | Bike Lane | Existing Bikeway with Facility Type Changes |
| 48 | Auraria Pkwy | Shared Sidewalk | Existing Bikeway |

## 4. The same thing at city scale

Everything above works on a whole city; it just needs the network. A
place name is geocoded, the Overpass box is clipped to the city’s
administrative boundary so Lakewood and Aurora do not leak in, and the
official layer is cut to the same polygon.

``` r

denver <- cl_bike_lanes("Denver, Colorado", cache = TRUE)
official <- cl_fetch_official("denver", bbox = attr(denver, "cl_boundary"))
cl_compare(denver, official)
```

Two things to keep in mind at that scale:

- **Overpass is a shared public server.** It rate-limits by address and
  refuses long queries when busy.
  [`cl_bike_lanes()`](https://mjorden.github.io/cyclelanes/reference/cl_bike_lanes.md)
  retries with backoff, `tile = 0.12` splits a city into small queries
  that pass more easily, and `cache = TRUE` means a re-run of the script
  never touches the server.
- **`shared_use_path` is where OSM is generous.** Park footways tagged
  `bicycle=designated` count; `strict = TRUE` drops the ones with no
  paved surface tag when you want on-road-quality kilometres.

## Provenance

OpenStreetMap data is © OpenStreetMap contributors, ODbL. The Denver
layer is the City and County of Denver’s Denver Moves: Bikes 2025
bikeway inventory, via the Denver Open Data Catalog.
`denver_lodo$fetched` records when both were fetched: 2026-09-03.
