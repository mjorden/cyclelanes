#' Bike lanes for a place, fetched from OpenStreetMap and classified
#'
#' Convenience wrapper: [cl_fetch_osm()] followed by [cl_classify()], with
#' non-facility ways dropped by default.
#'
#' @inheritParams cl_fetch_osm
#' @inheritParams cl_classify
#' @param ... Passed to [cl_fetch_osm()]: `overpass_url`, `retries`, `tile`,
#'   `cache`, `cache_dir`, `cache_max_age`, `backend`, `extract_dir`,
#'   `max_extract_mb`, `date`.
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
  attr(out, "cl_backend") <- attr(raw, "cl_backend")
  attr(out, "cl_date") <- attr(raw, "cl_date")
  attr(out, "cl_source") <- "openstreetmap"
  out
}

#' How a place's bike network has grown
#'
#' Fetches the network as it was on each of `dates` through Overpass's
#' attic data, classifies it, and stacks the [cl_summary()] of each
#' snapshot with a `date` column: kilometres by facility type over time.
#'
#' Attic queries are slow and the public server rate-limits them, so use
#' yearly steps, keep `cache = TRUE` (the default here), and expect a
#' whole city to take a few minutes per date. Snapshots before roughly
#' 2012 are thin because attic data starts with the ODbL licence change.
#'
#' @inheritParams cl_fetch_osm
#' @param dates A vector of `Date`s or `"YYYY-MM-DD"` strings.
#' @param by Passed to [cl_summary()].
#' @param ... Passed to [cl_bike_lanes()]: `drop_none`, `strict`, `timeout`,
#'   `retries`, `overpass_url`, `tile`, `cache_dir`, `cache_max_age`.
#' @return A data frame: `date`, then the columns of [cl_summary()]. A date
#'   whose fetch fails is skipped with a warning.
#' @examples
#' \dontrun{
#' growth <- cl_timeline("Boulder, Colorado", dates = paste0(2014:2026, "-01-01"))
#' subset(growth, facility_type == "protected_lane")
#' }
#' @export
cl_timeline <- function(place, dates, by = "facility_type", clip = TRUE, cache = TRUE, ...) {
  dates <- sort(unique(as.Date(dates)))
  out <- list()
  for (i in seq_along(dates)) {
    d <- dates[i]
    lanes <- tryCatch(
      cl_bike_lanes(place, clip = clip, cache = cache, date = d, ...),
      error = function(e) {
        rlang::warn(c(sprintf("Snapshot for %s failed and was skipped.", format(d)), x = conditionMessage(e)))
        NULL
      }
    )
    if (is.null(lanes)) next
    s <- if (nrow(lanes)) cl_summary(lanes, by = by) else NULL
    if (!is.null(s) && nrow(s)) out[[length(out) + 1L]] <- cbind(date = d, s, stringsAsFactors = FALSE)
  }
  if (!length(out)) return(data.frame(date = as.Date(character())))
  res <- do.call(rbind, out)
  rownames(res) <- NULL
  res
}
