# The cyclelanes facility taxonomy

Every facility in the package – whether it came from OpenStreetMap or a
city's official inventory – is classified into one of these levels,
ordered from most to least physically separated from motor traffic:

## Usage

``` r
cl_facility_levels()
```

## Value

A character vector of level names in protection order.

## Details

|  |  |  |
|----|----|----|
| level | meaning | typical OSM tagging |
| `separated_path` | dedicated off-street cycleway or trail | `highway=cycleway` |
| `shared_use_path` | off-street path shared with pedestrians | `highway=path/footway` + `bicycle=designated`; `highway=cycleway` + `segregated=no` or `foot=designated` |
| `protected_lane` | on-street, physically separated (curb, bollards, parking) | `cycleway=track` |
| `buffered_lane` | painted lane with a painted buffer | `cycleway=lane` + `cycleway:buffer=*` |
| `painted_lane` | painted lane, no buffer | `cycleway=lane` |
| `neighborhood_bikeway` | low-traffic street designated for bikes | `bicycle_road=yes`, `cyclestreet=yes` |
| `bus_bike_lane` | shared bus and bike lane | `cycleway=share_busway` |
| `shared_lane` | sharrows / shared general-traffic lane | `cycleway=shared_lane` |
| `shoulder` | rideable paved shoulder | `cycleway=shoulder` |
| `none` | no facility | `cycleway=no`, unrecognised, or absent; sidewalks (`footway=sidewalk`) whatever their `bicycle` tag |
