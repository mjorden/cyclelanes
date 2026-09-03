# Quick map of classified bike lanes

A `ggplot2` map coloured by `facility_type`. Requires `ggplot2`.

## Usage

``` r
cl_plot(
  x,
  title = NULL,
  linewidth = 0.6,
  colour = c("facility_type", "type_match")
)
```

## Arguments

- x:

  An `sf` with a `facility_type` column.

- title:

  Optional plot title.

- linewidth:

  Line width passed to
  [`ggplot2::geom_sf()`](https://ggplot2.tidyverse.org/reference/ggsf.html).

- colour:

  Column to colour by: `"facility_type"` (default, using
  [`cl_palette()`](https://mjorden.github.io/cyclelanes/reference/cl_palette.md))
  or `"type_match"` from a
  [`cl_compare()`](https://mjorden.github.io/cyclelanes/reference/cl_compare.md)
  layer, which draws agreeing segments green, disagreeing red, and
  unmatched grey.

## Value

A `ggplot` object.

## Examples

``` r
if (requireNamespace("ggplot2", quietly = TRUE)) {
  cl_plot(cl_classify(denver_lodo$osm, drop_none = TRUE), title = "Downtown Denver (OSM)")
}

if (FALSE) { # \dontrun{
cl_plot(cl_bike_lanes("Denver, Colorado"), title = "Denver bike facilities (OSM)")
} # }
```
