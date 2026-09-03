# Where cached Overpass results live

`cl_cache_dir()` returns the directory
[`cl_fetch_osm()`](https://mjorden.github.io/cyclelanes/reference/cl_fetch_osm.md)
uses when `cache = TRUE`: the `CYCLELANES_CACHE_DIR` environment
variable if set, otherwise the per-user cache directory from
[`tools::R_user_dir()`](https://rdrr.io/r/tools/userdir.html).
`cl_cache_clear()` deletes every cached result in it.

## Usage

``` r
cl_cache_dir()

cl_cache_clear(cache_dir = cl_cache_dir())
```

## Arguments

- cache_dir:

  Directory to clear.

## Value

`cl_cache_dir()`: a path. `cl_cache_clear()`: the number of files
removed, invisibly.

## Examples

``` r
cl_cache_dir()
#> [1] "/home/runner/.cache/R/cyclelanes"
```
