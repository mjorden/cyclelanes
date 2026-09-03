# Summarise facility length by type

Works on either layer: the OpenStreetMap output of
[`cl_bike_lanes()`](https://mjorden.github.io/cyclelanes/reference/cl_bike_lanes.md)
or the official output of
[`cl_fetch_official()`](https://mjorden.github.io/cyclelanes/reference/cl_fetch_official.md).

## Usage

``` r
cl_summary(x, by = "facility_type")
```

## Arguments

- x:

  An `sf` with a `facility_type` column (or whatever `by` names).

- by:

  Column(s) to group on. Default `"facility_type"`; for the official
  Denver layer `c("facility_type", "status")` is informative.

## Value

A data frame with `n_segments`, `length_km`, `length_mi`, and `share`
(fraction of total length) per group. Empty groups of a factor are
omitted.

## Examples

``` r
cl_summary(cl_classify(denver_lodo$osm, drop_none = TRUE))
#>     facility_type n_segments length_km length_mi      share
#> 1  separated_path         90  5.457209 3.3909516 0.19817790
#> 2 shared_use_path         53  2.292066 1.4242231 0.08323609
#> 3  protected_lane        162 12.726186 7.9076827 0.46214990
#> 4   buffered_lane         18  1.690104 1.0501815 0.06137591
#> 5    painted_lane         66  4.070209 2.5291097 0.14780915
#> 6     shared_lane         24  1.301149 0.8084959 0.04725105
cl_summary(denver_lodo$official, by = c("facility_type", "status"))
#>     facility_type                                      status n_segments
#> 1  separated_path                            Existing Bikeway          7
#> 2 shared_use_path                            Existing Bikeway          8
#> 3  protected_lane                            Existing Bikeway          5
#> 4  protected_lane Existing Bikeway with Facility Type Changes          1
#> 5  protected_lane       Existing Bikeway with Future Upgrades         15
#> 6  protected_lane                              Future Bikeway          1
#> 7   buffered_lane Existing Bikeway with Facility Type Changes          4
#> 8    painted_lane                            Existing Bikeway          1
#> 9    painted_lane Existing Bikeway with Facility Type Changes         13
#>   length_km   length_mi        share
#> 1 1.7943703 1.114969680 0.1004782634
#> 2 1.1126812 0.691387855 0.0623061347
#> 3 3.1650412 1.966664817 0.1772308872
#> 4 0.0124219 0.007718606 0.0006955814
#> 5 7.5451383 4.688330134 0.4225005206
#> 6 0.2931947 0.182182705 0.0164178472
#> 7 0.9652033 0.599749326 0.0540479009
#> 8 0.1269705 0.078895774 0.0071098887
#> 9 2.8432721 1.766726799 0.1592129759
if (FALSE) { # \dontrun{
cl_summary(cl_bike_lanes("Boulder, Colorado"))
} # }
```
