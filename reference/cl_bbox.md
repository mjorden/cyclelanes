# Resolve a place into a WGS84 bounding box

Accepts the same `place` argument as every fetch function in the package
and returns a bounding box in longitude/latitude degrees.

## Usage

``` r
cl_bbox(place)
```

## Arguments

- place:

  One of:

  - a place name geocoded through Nominatim, e.g. `"Denver, Colorado"`
    (respect the Nominatim usage policy: at most one request per second,
    no bulk geocoding);

  - a numeric vector `c(xmin, ymin, xmax, ymax)` in WGS84 degrees;

  - an `sf`, `sfc`, or `bbox` object in any CRS;

  - the 2 x 2 matrix returned by
    [`osmdata::getbb()`](https://docs.ropensci.org/osmdata/reference/getbb.html).

## Value

A named numeric vector `c(xmin, ymin, xmax, ymax)`.

## Examples

``` r
cl_bbox(c(-105.02, 39.73, -104.97, 39.76))
#>    xmin    ymin    xmax    ymax 
#> -105.02   39.73 -104.97   39.76 
if (FALSE) { # \dontrun{
cl_bbox("Denver, Colorado")
} # }
```
