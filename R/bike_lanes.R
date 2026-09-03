#' Bike lanes for a place, fetched from OpenStreetMap and classified
#'
#' Convenience wrapper: [cl_fetch_osm()] followed by [cl_classify()], with
#' non-facility ways dropped by default.
#'
#' @inheritParams cl_fetch_osm
#' @inheritParams cl_classify
#' @param ... Passed to [cl_fetch_osm()]: `overpass_url`, `retries`, `tile`,
#'   `cache`, `cache_dir`, `cache_max_age`.
#' @return The classified `sf` described in [cl_classify()], with the queried
#'   bounding box in `attr(x, "cl_bbox")`, the fetch time in
#'   `attr(x, "cl_fetched")`, and `attr(x, "cl_source") == "openstreetmap"`.
#' @examples
#' \dontrun{
#' denver <- cl_bike_lanes("Denver, Colorado")
#' cl_summary(denver)
#' cl_plot(denver)
#' }
#' @export
cl_bike_lanes <- function(place, drop_none = TRUE, keep_tags = FALSE, strict = FALSE,
                          timeout = 180, clip = TRUE, ...) {
  raw <- cl_fetch_osm(place, timeout = timeout, clip = clip, ...)
  out <- cl_classify(raw, drop_none = drop_none, keep_tags = keep_tags, strict = strict)
  attr(out, "cl_bbox") <- attr(raw, "cl_bbox")
  attr(out, "cl_boundary") <- attr(raw, "cl_boundary")
  attr(out, "cl_fetched") <- attr(raw, "cl_fetched")
  attr(out, "cl_source") <- "openstreetmap"
  out
}
