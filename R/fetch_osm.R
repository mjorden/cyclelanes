# Overpass feature filters. Any way carrying one of these is a candidate for
# bicycle infrastructure; cl_classify() decides what it actually is.
.cl_osm_features <- c(
  '"highway"="cycleway"',
  '"cycleway"',
  '"cycleway:left"',
  '"cycleway:right"',
  '"cycleway:both"',
  '"bicycle"="designated"',
  '"bicycle_road"="yes"',
  '"cyclestreet"="yes"'
)

#' Fetch raw bicycle-related ways from OpenStreetMap
#'
#' Queries the Overpass API for every way inside `place` that carries a tag
#' which can denote bicycle infrastructure: `highway=cycleway`, any
#' `cycleway`, `cycleway:left`, `cycleway:right` or `cycleway:both` tag,
#' `bicycle=designated`, `bicycle_road=yes`, or `cyclestreet=yes`. The result
#' is *unclassified*: many of these ways (a footway with `bicycle=designated`,
#' a road tagged `cycleway=no`) are not facilities. Pass it to
#' [cl_classify()] or use [cl_bike_lanes()] which does both.
#'
#' @inheritParams cl_bbox
#' @param timeout Overpass server timeout in seconds. City-scale queries can
#'   take a minute or more; the public Overpass instance rejects long-running
#'   queries, so keep `place` to a metro area or smaller.
#' @return An `sf` object of `LINESTRING`s in WGS84 (EPSG:4326) with the raw
#'   OSM tag columns present in the area. A zero-row `sf` if nothing matched.
#'   The WGS84 bounding box queried is stored in `attr(x, "cl_bbox")` and the
#'   fetch time in `attr(x, "cl_fetched")`.
#' @examples
#' \dontrun{
#' raw <- cl_fetch_osm(c(-105.00, 39.74, -104.98, 39.75))
#' nrow(raw)
#' }
#' @export
cl_fetch_osm <- function(place, timeout = 180) {
  bb <- cl_bbox(place)
  q <- osmdata::opq(bbox = bb, timeout = timeout)
  q <- osmdata::add_osm_features(q, features = .cl_osm_features)
  res <- osmdata::osmdata_sf(q)

  lines <- res$osm_lines
  if (is.null(lines) || nrow(lines) == 0L) {
    rlang::warn("Overpass returned no bicycle-tagged ways for this area.")
    lines <- .empty_osm_sf()
  } else {
    lines <- sf::st_as_sf(lines)
    lines <- sf::st_transform(lines, 4326)
    rownames(lines) <- NULL
  }
  attr(lines, "cl_bbox") <- bb
  attr(lines, "cl_fetched") <- Sys.time()
  lines
}

.empty_osm_sf <- function() {
  sf::st_sf(
    osm_id = character(),
    geometry = sf::st_sfc(crs = 4326)
  )
}
