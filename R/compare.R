#' Compare OpenStreetMap bike lanes against an official inventory
#'
#' Measures how much of each layer lies within `tolerance` metres of the
#' other. A segment's *matched fraction* is the share of its length inside a
#' buffer around the other layer, so it is 1 where both sources agree a
#' facility exists and 0 where one source has something the other lacks.
#' The comparison is purely spatial: it does not check that the two sources
#' agree on the *type* of facility, only on its presence.
#'
#' @param osm An `sf` from [cl_bike_lanes()] or [cl_classify()].
#' @param official An `sf` from [cl_fetch_official()].
#' @param tolerance Match distance in metres. Fifteen metres absorbs the
#'   usual centreline-vs-curb offset between sources without bridging
#'   parallel streets.
#' @return A list of class `cl_comparison`:
#'   * `summary`: one row per layer with `length_km`, `matched_km`,
#'     `matched_frac`;
#'   * `by_type`: the same broken down by `facility_type` within each layer;
#'   * `osm`, `official`: the inputs (WGS84) with a `matched_frac` column
#'     added, so unmatched segments can be mapped;
#'   * `tolerance`.
#' @examples
#' \dontrun{
#' osm <- cl_bike_lanes("Denver, Colorado")
#' den <- cl_fetch_official("denver")
#' cmp <- cl_compare(osm, den)
#' cmp
#' cl_plot(dplyr::filter(cmp$official, matched_frac < 0.5),
#'         title = "Official facilities OSM does not know about")
#' }
#' @export
cl_compare <- function(osm, official, tolerance = 15) {
  .stop_if_not_sf(osm, "osm")
  .stop_if_not_sf(official, "official")
  if (nrow(osm) == 0L || nrow(official) == 0L) {
    rlang::abort("Both `osm` and `official` must have at least one feature.")
  }
  if (!is.numeric(tolerance) || length(tolerance) != 1L || tolerance <= 0) {
    rlang::abort("`tolerance` must be a single positive number of metres.")
  }
  for (nm in c("osm", "official")) {
    if (!"facility_type" %in% names(get(nm))) {
      rlang::abort(sprintf("`%s` has no `facility_type` column; classify it first.", nm))
    }
  }

  # Lengths are geodesic on the inputs so they agree with `length_m`;
  # the buffer/intersection runs in a projected CRS.
  o_len <- .length_m(osm)
  f_len <- .length_m(official)
  crs <- .utm_crs(osm)
  o <- sf::st_transform(osm, crs)
  f <- sf::st_transform(official, crs)
  o$matched_frac <- .covered_frac(o, f, tolerance)
  f$matched_frac <- .covered_frac(f, o, tolerance)

  summary <- data.frame(
    layer = c("osm", "official"),
    n_segments = c(nrow(o), nrow(f)),
    length_km = c(sum(o_len), sum(f_len)) / 1000,
    matched_km = c(sum(o_len * o$matched_frac), sum(f_len * f$matched_frac)) / 1000,
    stringsAsFactors = FALSE
  )
  summary$matched_frac <- ifelse(summary$length_km > 0,
                                 summary$matched_km / summary$length_km, NA_real_)

  by_type <- rbind(.matched_by_type(o, o_len, "osm"),
                   .matched_by_type(f, f_len, "official"))

  structure(
    list(
      summary = summary,
      by_type = by_type,
      osm = sf::st_transform(o, 4326),
      official = sf::st_transform(f, 4326),
      tolerance = tolerance
    ),
    class = "cl_comparison"
  )
}

# Fraction of each feature in x lying within `tolerance` of any feature in y.
# Both must share a projected CRS in metres.
.covered_frac <- function(x, y, tolerance) {
  geom <- sf::st_geometry(x)
  total <- .length_m(geom)
  buf <- sf::st_union(sf::st_buffer(sf::st_geometry(y), tolerance))

  ids <- sf::st_sf(.id = seq_along(geom), geometry = geom)
  sf::st_agr(ids) <- "constant"
  inter <- suppressWarnings(sf::st_intersection(ids, buf))

  covered <- numeric(length(geom))
  if (nrow(inter) > 0L) {
    lens <- .length_m(inter)
    sums <- tapply(lens, factor(inter$.id, levels = seq_along(geom)), sum)
    covered <- as.numeric(sums)
    covered[is.na(covered)] <- 0
  }
  ifelse(total > 0, pmin(covered / total, 1), 0)
}

.matched_by_type <- function(x, len, layer) {
  d <- data.frame(
    facility_type = x$facility_type,
    len = len,
    matched = len * x$matched_frac
  )
  out <- d |>
    dplyr::group_by(.data$facility_type) |>
    dplyr::summarise(
      n_segments = dplyr::n(),
      length_km = sum(.data$len) / 1000,
      matched_frac = ifelse(sum(.data$len) > 0, sum(.data$matched) / sum(.data$len), NA_real_),
      .groups = "drop"
    ) |>
    dplyr::arrange(.data$facility_type)
  out <- as.data.frame(out)
  cbind(layer = layer, out, stringsAsFactors = FALSE)
}

#' @export
print.cl_comparison <- function(x, ...) {
  cat(sprintf("<cl_comparison> tolerance = %g m\n\n", x$tolerance))
  s <- x$summary
  s$length_km <- round(s$length_km, 1)
  s$matched_km <- round(s$matched_km, 1)
  s$matched_frac <- round(s$matched_frac, 3)
  print(s, row.names = FALSE)
  cat("\nBy facility type:\n")
  b <- x$by_type
  b$length_km <- round(b$length_km, 1)
  b$matched_frac <- round(b$matched_frac, 3)
  print(b, row.names = FALSE)
  invisible(x)
}
