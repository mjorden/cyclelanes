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
#' @param clip Overpass only takes a bounding box, and the box around a city
#'   usually spills into its neighbours. `TRUE` (the default) clips the result
#'   to the place's administrative boundary from [cl_boundary()] when `place`
#'   is a name; ways crossing the boundary are cut at it. Pass an `sf`/`sfc`
#'   polygon to clip to your own boundary with any kind of `place`, or
#'   `FALSE` to keep the whole box. Ignored for bbox and `sf` inputs unless a
#'   polygon is supplied.
#' @return An `sf` object of `LINESTRING`s in WGS84 (EPSG:4326) with the raw
#'   OSM tag columns present in the area. A zero-row `sf` if nothing matched.
#'   The WGS84 bounding box queried is stored in `attr(x, "cl_bbox")`, the
#'   clipping polygon (if any) in `attr(x, "cl_boundary")`, and the fetch
#'   time in `attr(x, "cl_fetched")`.
#' @examples
#' \dontrun{
#' raw <- cl_fetch_osm(c(-105.00, 39.74, -104.98, 39.75))
#' nrow(raw)
#' }
#' @export
cl_fetch_osm <- function(place, timeout = 180, clip = TRUE) {
  bb <- cl_bbox(place)
  boundary <- .resolve_clip(place, clip)

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
    if (!is.null(boundary)) lines <- .clip_lines(lines, boundary)
  }
  attr(lines, "cl_bbox") <- bb
  attr(lines, "cl_boundary") <- boundary
  attr(lines, "cl_fetched") <- Sys.time()
  lines
}

# Work out the clipping polygon (or NULL) from `place` and `clip`.
.resolve_clip <- function(place, clip) {
  if (inherits(clip, c("sf", "sfc"))) return(cl_boundary(clip))
  if (!is.logical(clip) || length(clip) != 1L || is.na(clip)) {
    rlang::abort("`clip` must be TRUE, FALSE, or an sf/sfc polygon.")
  }
  if (!clip || !is.character(place)) return(NULL)
  tryCatch(cl_boundary(place), error = function(e) {
    rlang::warn(c("Could not fetch a boundary polygon; returning the whole bounding box.",
                  i = conditionMessage(e)))
    NULL
  })
}

.empty_osm_sf <- function() {
  sf::st_sf(
    osm_id = character(),
    geometry = sf::st_sfc(crs = 4326)
  )
}
